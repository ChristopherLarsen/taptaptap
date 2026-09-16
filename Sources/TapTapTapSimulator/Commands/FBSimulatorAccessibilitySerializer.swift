/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import AppKit
import TapTapTapCore
import Foundation

/// Serializes a translated element tree into JSON-compatible dictionaries (nested format).
/// The values mirror the old SimulatorBridge implementation for downstream compatibility.
enum FBSimulatorAccessibilitySerializer {

  private static let axPrefix = "AX"

  private static func ensureJSONSerializable(_ object: Any?) -> Any {
    guard let object else {
      return NSNull()
    }
    if JSONSerialization.isValidJSONObject([object]) {
      return object
    }
    return String(describing: object)
  }

  static func nestedDescription(fromElement element: FBAXPlatformElement, token: String, keys: Set<FBAXKeys>) -> [String: Any] {
    var values = accessibilityDictionary(forElement: element, token: token, keys: keys)
    var childrenValues: [[String: Any]] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      childrenValues.append(nestedDescription(fromElement: child, token: token, keys: keys))
    }
    values["children"] = childrenValues
    return values
  }

  /// Non-hierarchical (flat) output: every element in the tree, serialized independently in
  /// traversal order, with no `children` key. Ported from idb's pinned `flatRecursiveDescription`
  /// (`idb/FBSimulatorControl/Commands/FBSimulatorAccessibilitySerializer.swift`) — the traversal
  /// itself (which elements, how many) is identical to `nestedDescription`; only the JSON shape
  /// differs. See AUDIT.md §6 for why this does not, by itself, change the element count idb and
  /// taptaptap report for the same screen.
  static func flatRecursiveDescription(fromElement element: FBAXPlatformElement, token: String, keys: Set<FBAXKeys>) -> [[String: Any]] {
    var values: [[String: Any]] = []
    values.append(accessibilityDictionary(forElement: element, token: token, keys: keys))
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      values.append(contentsOf: flatRecursiveDescription(fromElement: child, token: token, keys: keys))
    }
    return values
  }

  static func accessibilityDictionary(forElement element: FBAXPlatformElement, token: String, keys: Set<FBAXKeys>) -> [String: Any] {
    // The token must always be set so that the right delegate callback is used.
    element.axSetBridgeDelegateToken(token)

    var values: [String: Any] = [:]

    func include(_ key: FBAXKeys, _ value: @autoclosure () -> Any?) {
      guard keys.contains(key) else {
        return
      }
      values[key.rawValue] = ensureJSONSerializable(value())
    }

    let frame = element.axFrame()

    // Role feeds both `role` and the synthetic `type` (role without the "AX" prefix).
    var rawRole: String?
    if keys.contains(.role) {
      rawRole = element.axRole()
      values[FBAXKeys.role.rawValue] = ensureJSONSerializable(rawRole)
    }
    var role: String?
    if keys.contains(.type) {
      if rawRole == nil {
        rawRole = element.axRole()
      }
      if let rawRole, rawRole.hasPrefix(axPrefix) {
        role = String(rawRole.dropFirst(2))
      } else {
        role = rawRole
      }
    }

    include(.label, element.axLabel())
    if keys.contains(.frame) {
      values[FBAXKeys.frame.rawValue] = NSStringFromRect(frame)
    }
    include(.value, element.axValue())
    include(.uniqueID, element.axIdentifier())
    if keys.contains(.type) {
      values[FBAXKeys.type.rawValue] = ensureJSONSerializable(role)
    }
    include(.title, element.axTitle())
    if keys.contains(.frameDict) {
      values[FBAXKeys.frameDict.rawValue] = [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.size.width,
        "height": frame.size.height,
      ]
    }
    include(.help, element.axHelp())
    include(.enabled, element.axIsEnabled())
    include(.customActions, element.axCustomActionNames())
    include(.roleDescription, element.axRoleDescription())
    include(.subrole, element.axSubrole())
    include(.contentRequired, element.axIsRequired())
    include(.pid, element.axTranslationPid)
    return values
  }
}
