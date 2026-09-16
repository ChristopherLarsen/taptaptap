/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import AppKit
import CoreSimulator
import TapTapTapCore
import Foundation

// MARK: - FBSimulator (translation dispatcher construction)

extension FBSimulator {

  // Process-wide singleton: AXPTranslator has a single bridgeTokenDelegate slot, so exactly one
  // dispatcher backs every simulator. The lazy `static let` initialiser is thread-safe.
  private nonisolated(unsafe) static let sharedAccessibilityTranslationDispatcher: FBAXTranslationDispatcher = {
    let translator = unsafeBitCast(AXPTranslator.sharedInstance() as AnyObject, to: AXPTranslator.self)
    let dispatcher = FBAXTranslationDispatcher(translator: translator)
    translator.bridgeTokenDelegate = dispatcher
    return dispatcher
  }()

  var accessibilityTranslationDispatcher: FBAXTranslationDispatcher {
    FBSimulator.sharedAccessibilityTranslationDispatcher
  }
}

public final class FBSimulatorAccessibilityCommands: NSObject, AsyncAccessibilityOperations {

  private static let coreSimulatorBridgeServiceName = "com.apple.CoreSimulator.bridge"

  static func requiresAccessibilityBootstrap(for runtimeVersion: OperatingSystemVersion) -> Bool {
    runtimeVersion.majorVersion >= 27
  }

  private weak var simulator: FBSimulator?


  @objc(initWithSimulator:)
  public init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  @objc(commandsWithTarget:)
  public class func commands(with target: FBSimulator) -> Self {
    self.init(simulator: target)
  }

  // MARK: Translation Dispatcher

  /// The simulator's process-wide shared translation dispatcher.
  private var resolvedDispatcher: FBAXTranslationDispatcher? {
    simulator?.accessibilityTranslationDispatcher
  }

  // MARK: AsyncAccessibilityOperations

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try validateAccessibility()
    let request = FBAXTranslationRequest(kind: .point(point))
    return try await accessibilityElement(request: request, remediationPermitted: false)
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try validateAccessibility()
    let request = FBAXTranslationRequest(kind: .frontmostApplication)
    return try await accessibilityElement(request: request, remediationPermitted: true)
  }

  // MARK: Private

  // Uses the CoreSimulator accessibility API via
  // -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:].
  // This API requires Xcode 12+ to have been installed on the host at some point.
  private func validateAccessibility() throws {
    guard let simulator else {
      throw FBAccessibilityError.simulatorDeallocated
    }
    guard simulator.state == .booted else {
      throw FBAccessibilityError.simulatorNotBooted(description: "\(simulator)")
    }
    let selector = NSSelectorFromString("sendAccessibilityRequestAsync:completionQueue:completionHandler:")
    guard simulator.device.responds(to: selector) else {
      throw FBAccessibilityError.accessibilityUnavailable
    }
    try FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(simulator.logger)
    if Self.requiresAccessibilityBootstrap(for: simulator.osVersion.version) {
      try FBSimulatorControlFrameworkLoader.bootstrapAccessibility(
        forSimulatorDevice: simulator.device,
        timeout: 5,
        logger: simulator.logger
      )
    }
  }

  // Returns an FBAccessibilityElement wrapping the platform element for the given request.
  // The handle owns the request's token and pops it on close.
  //
  // When remediationPermitted and a stale SpringBoard is detected (zero accessibility frame +
  // dead pid), the original request's token is popped manually (it is not wrapped in a handle
  // yet at that point), CoreSimulatorBridge is restarted, and the lookup retries with a fresh
  // request. The retry passes remediationPermitted=false, bounding it to a single attempt.
  private func accessibilityElement(request: FBAXTranslationRequest, remediationPermitted: Bool) async throws -> FBAccessibilityElement {
    guard let simulator else {
      throw FBAccessibilityError.simulatorDeallocated
    }
    guard let dispatcher = resolvedDispatcher else {
      throw FBAccessibilityError.dispatcherUnavailable
    }
    let element = try await dispatcher.platformElement(withRequest: request, simulator: simulator)
    if !remediationPermitted {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher)
    }
    if try await !Self.remediationRequired(forSimulator: simulator, element: element) {
      return FBAccessibilityElement(element: element, request: request, dispatcher: dispatcher)
    }
    // The request's token was pushed by the dispatcher but is not yet wrapped in an
    // FBAccessibilityElement, so pop it manually before discarding the request.
    dispatcher.popRequest(request)
    let nextRequest = request.cloneWithNewToken()
    try await Self.remediateSpringBoard(forSimulator: simulator)
    return try await accessibilityElement(request: nextRequest, remediationPermitted: false)
  }

  private static func remediationRequired(forSimulator simulator: FBSimulator, element: FBAXPlatformElement) async throws -> Bool {
    // A quick check: a non-zero accessibility frame indicates a healthy element.
    if !element.axFrame().equalTo(.zero) {
      return false
    }
    // Otherwise confirm whether the translation object's pid represents a real process.
    // If it does not, we likely got the pid of a crashed SpringBoard; restarting
    // CoreSimulatorBridge lets launchd bring a fresh SpringBoard (and bridge) back up.
    let pid = element.axTranslationPid
    do {
      _ = try await simulator.serviceName(forProcessIdentifier: pid)
      return false
    } catch {
      simulator.logger?.log("Frontmost accessibility hierarchy is stale: the root element has a zero frame and its owning pid \(pid) is no longer a registered launchd service. SpringBoard has crashed and CoreSimulator's \(coreSimulatorBridgeServiceName) is still bound to the dead pid; restarting \(coreSimulatorBridgeServiceName) to recover.")
      return true
    }
  }

  private static func remediateSpringBoard(forSimulator simulator: FBSimulator) async throws {
    do {
      _ = try await simulator.stopService(withName: coreSimulatorBridgeServiceName)
    } catch {
      throw FBAccessibilityError.springBoardRemediationFailed(serviceName: coreSimulatorBridgeServiceName)
    }
  }
}

// MARK: - FBSimulator+AsyncAccessibilityCommands

extension FBSimulator: AsyncAccessibilityCommands {

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try await accessibilityCommands().accessibilityElement(at: point)
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try await accessibilityCommands().accessibilityElementForFrontmostApplication()
  }
}
