/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import TapTapTapArguments
import TapTapTapCore

/// Which elements a `describe-all` read reports. idb: `--filter <all|interactable>`
/// (`_add_filter_arg` in `idb/cli/commands/accessibility.py`, `facebook/idb` v1.5.7,
/// `efaab3199d85db72a52f4a3cf527cbffe1ad42ea`). idb wires this flag onto `describe-all` only —
/// `AccessibilityInfoAtPointCommand` never calls `_add_filter_arg` — so `describe-point` gets no
/// `--filter` here either, matching idb exactly (confirmed against that file, not assumed).
///
/// Ported from idb's structural fallback
/// (`FBSimulatorControl/Commands/AccessibilityElementFiltering.swift` +
/// `AXRoleVocabulary.swift` at the same tag), adapted from idb's typed
/// `FBAccessibilityDocumentElement` model to taptaptap's `[String: Any]` serialized JSON. idb's
/// other narrowing — an opt-in, per-element "interactable verdict" hit-test against the backend,
/// applied only when a caller explicitly requests it — is **not** ported; see AUDIT.md §7 for the
/// scope boundary and the observed count this leaves unclosed.
enum AccessibilityElementFilter: String, CaseIterable, ExpressibleByArgument, Sendable {
  /// Every element the read walked. The identity narrowing — no decode/re-encode, no behavior
  /// change from before this phase.
  case all
  /// Only elements with a non-empty `AXLabel`, a non-empty `AXUniqueId`, or an interactable
  /// `type`.
  case interactable
}

/// Post-order hoisting: keep `element` if it passes, otherwise promote its kept descendants into
/// its place. This is what stops the filter over-reaching — a real button nested inside ten
/// layers of unlabeled `AXGroup` survives while the groups themselves don't.
enum AccessibilityElementRetention {
  /// A dictionary with no `children` key never gains one, so a flat read's elements stay flat.
  /// On a flat array (no element carries `children`) this degenerates to a plain predicate
  /// filter: a childless dictionary that fails `keeps` has no descendants to hoist.
  static func retained(
    from element: [String: Any],
    where keeps: ([String: Any]) -> Bool
  ) -> [[String: Any]] {
    let children = element["children"] as? [[String: Any]] ?? []
    let keptChildren = children.flatMap { retained(from: $0, where: keeps) }
    guard keeps(element) else {
      return keptChildren
    }
    var kept = element
    if element["children"] != nil {
      kept["children"] = keptChildren
    }
    return [kept]
  }

  static func retaining(
    _ elements: [[String: Any]],
    where keeps: ([String: Any]) -> Bool
  ) -> [[String: Any]] {
    elements.flatMap { retained(from: $0, where: keeps) }
  }
}

extension AccessibilityElementFilter {
  /// idb's 20-name interactable role vocabulary, ported verbatim from `AXRoleVocabulary.swift`'s
  /// `interactableRoles`.
  private static let interactableRoles: Set<String> = [
    "Button", "Cell", "TextField", "SecureTextField", "SearchField", "Switch", "Toggle", "Link",
    "MenuItem", "Slider", "CheckBox", "RadioButton", "SegmentedControl", "Stepper", "PopUpButton",
    "Picker", "PickerWheel", "Tab", "Key", "DisclosureTriangle",
  ]

  /// The elements this filter keeps, with kept descendants hoisted into the place of anything
  /// dropped. `.all` is the identity and returns the input untouched.
  private func applied(to elements: [[String: Any]]) -> [[String: Any]] {
    guard self == .interactable else {
      return elements
    }
    return AccessibilityElementRetention.retaining(elements, where: Self.keepsInteractable)
  }

  /// Applies this filter to already-serialized `describe-all` JSON. `.all` returns `data`
  /// unchanged — no decode/re-encode — so the default, unfiltered path (and every internal
  /// caller that never passes a filter: `describe-point`, `--label`/`--id` targeting, `batch`)
  /// pays nothing extra and sees no behavior change.
  ///
  /// The top-level shape taptaptap ever hands this is a JSON array (one root dictionary in
  /// nested format, or the flat traversal order in flat format) — `describe-all` is the only
  /// caller, and its frontmost-application read always serializes to an array. A shape this
  /// doesn't recognize is returned unchanged rather than treated as an error.
  func applied(toJSON data: Data) throws -> Data {
    guard self == .interactable else {
      return data
    }
    guard let elements = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return data
    }
    let filtered = applied(to: elements)
    return try JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted])
  }

  /// idb's structural fallback: a non-empty label, a non-empty identifier, or an interactable
  /// role. Matched against taptaptap's `type` field, which the serializer already reports with
  /// the `AX` prefix stripped (`AXButton` -> `Button`); the inline strip below is a defensive
  /// fallback for a raw `AX`-prefixed value, not something taptaptap's `type` field currently
  /// produces. idb's `normalizeRole` also demangles legacy-mangled Swift class names before
  /// matching; that branch is not ported here — taptaptap's roles come from
  /// `AXPMacPlatformElement.accessibilityRole()`, an `NSAccessibility.Role`, whose `rawValue` is
  /// always a standard `AX`-prefixed constant, never a mangled type name (checked against every
  /// distinct `role`/`type` value in `evidence-ab/json/*.json` and a fresh live `describe-all`
  /// capture on Settings — see AUDIT.md §7).
  private static func keepsInteractable(_ element: [String: Any]) -> Bool {
    if let label = element[FBAXKeys.label.rawValue] as? String, !label.isEmpty {
      return true
    }
    if let identifier = element[FBAXKeys.uniqueID.rawValue] as? String, !identifier.isEmpty {
      return true
    }
    if let type = element[FBAXKeys.type.rawValue] as? String {
      let normalized = type.hasPrefix("AX") ? String(type.dropFirst(2)) : type
      if interactableRoles.contains(normalized) {
        return true
      }
    }
    return false
  }
}
