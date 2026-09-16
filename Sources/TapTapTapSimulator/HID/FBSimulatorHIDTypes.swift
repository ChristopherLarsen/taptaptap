/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// The core, transport-agnostic HID value types. Every transport (Indigo, DTUHID) and the
/// `FBSimulatorHIDEvent` dispatch share these; they are intentionally independent of any one
/// transport's wire format. Each carries a single canonical `name` — the source of truth for the
/// string forms used in event descriptions and (upper-cased) in CLI arguments.

/// The direction of a HID event.
public enum FBSimulatorHIDDirection: Int32, Sendable, CaseIterable {
  case down = 1
  case up = 2

  /// The canonical lower-snake-case name for this direction.
  public var name: String {
    switch self {
    case .down: return "down"
    case .up: return "up"
    }
  }
}

/// A hardware button press.
public enum FBSimulatorHIDButton: Int32, Sendable, CaseIterable {
  case applePay = 1
  case homeButton = 2
  case lock = 3
  case sideButton = 4
  case siri = 5

  /// The canonical lower-snake-case name for this button.
  public var name: String {
    switch self {
    case .applePay: return "apple_pay"
    case .homeButton: return "home"
    case .lock: return "lock"
    case .sideButton: return "side_button"
    case .siri: return "siri"
    }
  }
}

/// Device orientation. Values match UIDeviceOrientation (1-4, excluding faceUp/faceDown).
