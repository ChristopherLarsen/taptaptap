/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import AccessibilityPlatformTranslation
import CoreSimulator
import TapTapTapCore
import Foundation

/// One accessibility translation request: the frontmost application or the element at a point.
/// The token routes AXPTranslator delegate callbacks back to this request's simulator device.
final class FBAXTranslationRequest {

  enum Kind {
    case frontmostApplication
    case point(CGPoint)
  }

  // Bound on each synchronous accessibility XPC round-trip. Healthy responses return well under
  // 1 s; the bound keeps a stalled accessibility service from hanging the caller.
  private static let defaultRequestTimeoutSeconds: TimeInterval = 5.0

  let kind: Kind
  let token: String
  var device: SimDevice?
  let requestTimeoutSeconds: TimeInterval

  init(kind: Kind) {
    self.kind = kind
    self.token = UUID().uuidString
    self.requestTimeoutSeconds = Self.defaultRequestTimeoutSeconds
  }

  func cloneWithNewToken() -> FBAXTranslationRequest {
    FBAXTranslationRequest(kind: kind)
  }

  func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    switch kind {
    case .frontmostApplication:
      return translator.frontmostApplication(withDisplayId: 0, bridgeDelegateToken: token)
    case .point(let point):
      return translator.object(at: point, displayId: 0, bridgeDelegateToken: token)
    }
  }

  func run(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) -> FBAccessibilityElementsResponse {
    switch kind {
    case .point:
      if options.nestedFormat {
        return FBAccessibilityElementsResponse(
          elements: FBSimulatorAccessibilitySerializer.nestedDescription(fromElement: element, token: token, keys: options.keys))
      }
      return FBAccessibilityElementsResponse(
        elements: FBSimulatorAccessibilitySerializer.accessibilityDictionary(forElement: element, token: token, keys: options.keys))
    case .frontmostApplication:
      if options.nestedFormat {
        return FBAccessibilityElementsResponse(
          elements: [FBSimulatorAccessibilitySerializer.nestedDescription(fromElement: element, token: token, keys: options.keys)])
      }
      return FBAccessibilityElementsResponse(
        elements: FBSimulatorAccessibilitySerializer.flatRecursiveDescription(fromElement: element, token: token, keys: options.keys))
    }
  }
}
