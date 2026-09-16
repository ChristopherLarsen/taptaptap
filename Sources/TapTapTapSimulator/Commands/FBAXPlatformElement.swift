/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import AccessibilityPlatformTranslation
import AppKit
import TapTapTapCore
import Foundation

/// Read-only accessors on a translated macOS platform element (`AXPMacPlatformElement`).
/// taptaptap exposes no accessibility actions (press, scroll, set value).
protocol FBAXPlatformElement: AnyObject {
  func axFrame() -> NSRect
  func axRole() -> String?
  func axLabel() -> String?
  func axValue() -> Any?
  func axIdentifier() -> String?
  func axTitle() -> String?
  func axHelp() -> String?
  func axRoleDescription() -> String?
  func axSubrole() -> String?
  func axIsEnabled() -> Bool
  func axIsRequired() -> Bool
  func axCustomActionNames() -> [String]
  func axChildren() -> [FBAXPlatformElement]
  var axTranslationPid: pid_t { get }
  func axSetBridgeDelegateToken(_ token: String?)
}

extension AXPMacPlatformElement: FBAXPlatformElement {
  func axFrame() -> NSRect { accessibilityFrame() }
  func axRole() -> String? { accessibilityRole()?.rawValue }
  func axLabel() -> String? { accessibilityLabel() }
  func axValue() -> Any? { accessibilityValue() }
  func axIdentifier() -> String? { accessibilityIdentifier() }
  func axTitle() -> String? { accessibilityTitle() }
  func axHelp() -> String? { accessibilityHelp() }
  func axRoleDescription() -> String? { accessibilityRoleDescription() }
  func axSubrole() -> String? { accessibilitySubrole()?.rawValue }
  func axIsEnabled() -> Bool { isAccessibilityEnabled() }
  func axIsRequired() -> Bool { isAccessibilityRequired() }
  func axCustomActionNames() -> [String] { (accessibilityCustomActions() ?? []).map { $0.name } }

  func axChildren() -> [FBAXPlatformElement] {
    (accessibilityChildren() ?? []).compactMap { $0 as? FBAXPlatformElement }
  }

  var axTranslationPid: pid_t { translation?.pid ?? 0 }
  func axSetBridgeDelegateToken(_ token: String?) { translation?.bridgeDelegateToken = token }
}
