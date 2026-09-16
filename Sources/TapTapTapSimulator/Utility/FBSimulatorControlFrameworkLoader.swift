/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import TapTapTapCore
import Foundation

// Runtime-only XCUIAutomation API surface (taptaptap 3e port of FBSimulatorControlFrameworkLoader.m).
// The classes are looked up by name and messaged through these @objc protocols via unsafeBitCast,
// the same shape as SimDeviceLegacyHIDClientMessaging; no link-time class reference is emitted.
// Each selector's availability is checked with respondsToSelector before it is sent.

@objc private protocol XCUIDeviceRemoteDaemonConnectionProviderClass {
  @objc(connectionProviderForSimDevice:)
  func connectionProvider(forSimDevice device: Any) -> AnyObject?
}

@objc private protocol XCUIDeviceRemoteAutomationSessionClass {
  @objc(requestSessionWithDaemonConnectionProvider:completion:)
  func requestSession(withDaemonConnectionProvider provider: Any, completion: @escaping (AnyObject?, NSError?) -> Void)
}

@objc private protocol XCUIDeviceRemoteAutomationSessionMessaging {
  @objc(invalidate)
  func invalidate()

  @objc(enableAutomationModeWithError:)
  func enableAutomationMode(withError error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool

  @objc(loadAccessibilityWithTimeout:reply:)
  func loadAccessibility(withTimeout timeout: Double, reply: @escaping (Bool, NSError?) -> Void)
}

private let accessibilityBootstrapErrorDomain = "com.facebook.FBSimulatorControl.AccessibilityBootstrap"

private func accessibilityBootstrapError(_ code: Int, _ description: String) -> NSError {
  NSError(domain: accessibilityBootstrapErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
}

private func classResponds(_ cls: AnyClass, to selector: Selector) -> Bool {
  // Equivalent of +[cls respondsToSelector:]: class methods live on the metaclass.
  guard let metaclass = object_getClass(cls) else {
    return false
  }
  return class_respondsToSelector(metaclass, selector)
}

private func invalidateAutomationSession(_ session: AnyObject) {
  guard session.responds(to: NSSelectorFromString("invalidate")) else {
    return
  }
  unsafeBitCast(session, to: XCUIDeviceRemoteAutomationSessionMessaging.self).invalidate()
}

/// One in-flight bootstrap per simulator device; concurrent callers wait on the owner's result.
private final class AccessibilityBootstrapAttempt {
  let group = DispatchGroup()
  // Written by the owning caller before `group.leave()`, read by waiters only after `group.wait()`.
  var success = false
  var error: Error?

  init() {
    group.enter()
  }
}

/// Holds the session delivered by the request completion. Once the caller times out, a session that
/// arrives late is invalidated instead of stored.
private final class AccessibilitySessionRequest {
  private let lock = NSLock()
  private var storedSession: AnyObject?
  private var storedError: NSError?
  private var timedOut = false

  func complete(session: AnyObject?, error: NSError?) {
    lock.lock()
    let wasTimedOut = timedOut
    if !wasTimedOut {
      storedSession = session
      storedError = error
    }
    lock.unlock()
    if wasTimedOut, let session {
      invalidateAutomationSession(session)
    }
  }

  func sessionByMarkingTimedOut() -> AnyObject? {
    lock.lock()
    defer { lock.unlock() }
    timedOut = true
    let session = storedSession
    storedSession = nil
    return session
  }

  var session: AnyObject? {
    lock.lock()
    defer { lock.unlock() }
    return storedSession
  }

  var error: NSError? {
    lock.lock()
    defer { lock.unlock() }
    return storedError
  }
}

/// Loads the private frameworks FBSimulatorControl depends on.
public final class FBSimulatorControlFrameworkLoader: FBControlCoreFrameworkLoader {

  /// The Frameworks needed for most operations.
  public static let essentialFrameworks = FBSimulatorControlFrameworkLoader(
    name: "FBSimulatorControl", frameworks: [FBWeakFramework.coreSimulator])

  /// The frameworks needed for Accessibility operations.
  public static let accessibilityFrameworks = FBSimulatorControlFrameworkLoader(
    name: "FBSimulatorControl", frameworks: [FBWeakFramework.accessibilityPlatformTranslation])

  /// The Xcode frameworks needed to bootstrap simulator Accessibility on Xcode 27+.
  public static let accessibilityAutomationFrameworks = FBSimulatorControlFrameworkLoader(
    name: "FBSimulatorControl", frameworks: [FBWeakFramework.xctDaemonControl, FBWeakFramework.xcuiAutomation])

  /// All of the Frameworks for operations involving the HID and Framebuffer.
  public static let xcodeFrameworks = FBSimulatorControlFrameworkLoader(
    name: "FBSimulatorControl", frameworks: [FBWeakFramework.simulatorKit])

  private static let bootstrapStateQueue = DispatchQueue(label: "com.facebook.FBSimulatorControl.AccessibilityBootstrap")
  // Guarded by bootstrapStateQueue. Weak keys: a deallocated SimDevice drops its entry.
  private static let bootstrapStates = NSMapTable<AnyObject, AccessibilityBootstrapAttempt>.weakToStrongObjects()

  /// Starts a short-lived remote automation session and asks it to load Accessibility.
  public static func bootstrapAccessibility(forSimulatorDevice simulatorDevice: AnyObject, timeout: TimeInterval, logger: FBControlCoreLogger?) throws {
    var attempt: AccessibilityBootstrapAttempt!
    var ownsAttempt = false
    bootstrapStateQueue.sync {
      if let existing = bootstrapStates.object(forKey: simulatorDevice) {
        attempt = existing
      } else {
        attempt = AccessibilityBootstrapAttempt()
        bootstrapStates.setObject(attempt, forKey: simulatorDevice)
        ownsAttempt = true
      }
    }
    if !ownsAttempt {
      attempt.group.wait()
      if !attempt.success {
        throw attempt.error ?? accessibilityBootstrapError(5, "Could not create the simulator remote automation session")
      }
      return
    }

    var bootstrapError: Error?
    do {
      try performAccessibilityBootstrap(forSimulatorDevice: simulatorDevice, timeout: timeout, logger: logger)
      attempt.success = true
    } catch {
      bootstrapError = error
      attempt.error = error
    }
    bootstrapStateQueue.sync {
      if bootstrapStates.object(forKey: simulatorDevice) === attempt {
        bootstrapStates.removeObject(forKey: simulatorDevice)
      }
    }
    attempt.group.leave()
    if let bootstrapError {
      throw bootstrapError
    }
  }

  private static func performAccessibilityBootstrap(forSimulatorDevice simulatorDevice: AnyObject, timeout: TimeInterval, logger: FBControlCoreLogger?) throws {
    try accessibilityAutomationFrameworks.loadPrivateFrameworks(logger)

    let providerSelector = NSSelectorFromString("connectionProviderForSimDevice:")
    guard let providerClass = NSClassFromString("XCUIDeviceRemoteDaemonConnectionProvider"), classResponds(providerClass, to: providerSelector) else {
      throw accessibilityBootstrapError(1, "XCUIDeviceRemoteDaemonConnectionProvider.connectionProviderForSimDevice: is unavailable")
    }
    guard let provider = unsafeBitCast(providerClass, to: XCUIDeviceRemoteDaemonConnectionProviderClass.self).connectionProvider(forSimDevice: simulatorDevice) else {
      throw accessibilityBootstrapError(2, "Could not create the simulator remote daemon connection provider")
    }

    let requestSelector = NSSelectorFromString("requestSessionWithDaemonConnectionProvider:completion:")
    guard let sessionClass = NSClassFromString("XCUIDeviceRemoteAutomationSession"), classResponds(sessionClass, to: requestSelector) else {
      throw accessibilityBootstrapError(3, "XCUIDeviceRemoteAutomationSession request API is unavailable")
    }

    let sessionSemaphore = DispatchSemaphore(value: 0)
    let sessionRequest = AccessibilitySessionRequest()
    unsafeBitCast(sessionClass, to: XCUIDeviceRemoteAutomationSessionClass.self).requestSession(withDaemonConnectionProvider: provider) { returnedSession, returnedError in
      sessionRequest.complete(session: returnedSession, error: returnedError)
      sessionSemaphore.signal()
    }
    if sessionSemaphore.wait(timeout: .now() + timeout) == .timedOut {
      if let lateSession = sessionRequest.sessionByMarkingTimedOut() {
        invalidateAutomationSession(lateSession)
      }
      throw accessibilityBootstrapError(4, "Timed out creating the simulator remote automation session")
    }
    guard let session = sessionRequest.session else {
      throw sessionRequest.error ?? accessibilityBootstrapError(5, "Could not create the simulator remote automation session")
    }
    // The ObjC original used @try/@finally with no @catch; defer gives the same invalidation on every
    // return and throw path.
    defer { invalidateAutomationSession(session) }
    let messaging = unsafeBitCast(session, to: XCUIDeviceRemoteAutomationSessionMessaging.self)

    if session.responds(to: NSSelectorFromString("enableAutomationModeWithError:")) {
      var enableError: NSError?
      guard messaging.enableAutomationMode(withError: &enableError) else {
        throw enableError ?? accessibilityBootstrapError(6, "Could not enable simulator automation mode")
      }
    }

    guard session.responds(to: NSSelectorFromString("loadAccessibilityWithTimeout:reply:")) else {
      throw accessibilityBootstrapError(7, "Remote automation session cannot load Accessibility")
    }
    let loadSemaphore = DispatchSemaphore(value: 0)
    let loadLock = NSLock()
    var loaded = false
    var loadError: NSError?
    messaging.loadAccessibility(withTimeout: timeout) { returnedLoaded, returnedError in
      loadLock.lock()
      loaded = returnedLoaded
      loadError = returnedError
      loadLock.unlock()
      loadSemaphore.signal()
    }
    if loadSemaphore.wait(timeout: .now() + timeout + 1) == .timedOut {
      throw accessibilityBootstrapError(8, "Timed out loading simulator Accessibility")
    }
    loadLock.lock()
    let didLoad = loaded
    let returnedLoadError = loadError
    loadLock.unlock()
    guard didLoad else {
      throw returnedLoadError ?? accessibilityBootstrapError(9, "The simulator rejected the Accessibility load request")
    }
    logger?.log("Bootstrapped simulator Accessibility through a short-lived remote automation session")
  }
}
