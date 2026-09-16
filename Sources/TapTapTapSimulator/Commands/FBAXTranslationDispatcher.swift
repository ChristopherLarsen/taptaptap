/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


@preconcurrency import AccessibilityPlatformTranslation
import CoreSimulator
import TapTapTapCore
import Foundation

private final class AXPResponseBox: @unchecked Sendable {
  var response: AXPTranslatorResponse?
}

/// The AXPTranslator bridge delegate. AXPTranslator is a process-wide singleton with a single
/// delegate slot, so one dispatcher serves every request, disambiguating by token under a lock.
final class FBAXTranslationDispatcher: NSObject, AXPTranslationTokenDelegateHelper {

  private weak var translator: AXPTranslator?
  private let callbackQueue: DispatchQueue
  private let lock = NSLock()
  private var tokenToRequest: [String: FBAXTranslationRequest] = [:]

  init(translator: AXPTranslator) {
    self.translator = translator
    self.callbackQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.callback")
    super.init()
  }

  // MARK: - Public

  func platformElement(withRequest request: FBAXTranslationRequest, simulator: FBSimulator) async throws -> FBAXPlatformElement {
    // The synchronous XPC round-trips driven below (via the delegate callback) must never run on
    // the main queue; this async method runs on the cooperative executor.
    request.device = simulator.device
    pushRequest(request)
    guard let translator, let translation = request.perform(withTranslator: translator) else {
      popRequest(request)
      throw FBAccessibilityError.noTranslationObject
    }
    translation.bridgeDelegateToken = request.token
    guard let element = translator.macPlatformElement(fromTranslation: translation) as? FBAXPlatformElement else {
      throw FBAccessibilityError.noTranslationObject
    }
    element.axSetBridgeDelegateToken(request.token)
    return element
  }

  func popRequest(_ request: FBAXTranslationRequest) {
    lock.lock()
    tokenToRequest.removeValue(forKey: request.token)
    lock.unlock()
  }

  // MARK: - Private

  private func pushRequest(_ request: FBAXTranslationRequest) {
    lock.lock()
    defer { lock.unlock() }
    tokenToRequest[request.token] = request
  }

  private func request(forToken token: String) -> FBAXTranslationRequest? {
    lock.lock()
    defer { lock.unlock() }
    return tokenToRequest[token]
  }

  private static func emptyResponse() -> AXPTranslatorResponse? {
    AXPTranslatorResponse.empty() as? AXPTranslatorResponse
  }

  // MARK: - AXPTranslationTokenDelegateHelper

  // The CoreSimulator accessibility API is asynchronous but AXPTranslator's delegation is
  // synchronous, so a DispatchGroup waits (bounded) for the response.
  func accessibilityTranslationDelegateBridgeCallback(withToken token: String) -> AXPTranslationCallback {
    guard let request = request(forToken: token) else {
      return { _ in Self.emptyResponse() }
    }
    let device = request.device
    let timeoutSeconds = request.requestTimeoutSeconds
    let callbackQueue = self.callbackQueue
    return { axRequest in
      let group = DispatchGroup()
      group.enter()
      let box = AXPResponseBox()
      axRequest?.clientType = 2
      device?.sendAccessibilityRequestAsync(axRequest, completionQueue: callbackQueue) { innerResponse in
        box.response = innerResponse
        group.leave()
      }
      if group.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        return Self.emptyResponse()
      }
      return box.response
    }
  }

  func accessibilityTranslationConvertPlatformFrame(toSystem rect: CGRect, withToken token: String) -> CGRect {
    rect
  }

  func accessibilityTranslationRootParent(withToken token: String) -> Any? {
    nil
  }
}
