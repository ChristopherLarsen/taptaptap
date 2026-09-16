/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// taptaptap 3e: Swift port of FBiOSTargetConstants.h/.m. Raw values and Swift spellings match the
// former NS_ENUM / NS_STRING_ENUM imports.

/// An enum representing states. The values here are not guaranteed to be stable over time and should
/// not be serialized. FBiOSTargetStateString is guaranteed to be stable over time.
@objc public enum FBiOSTargetState: UInt {
  case creating = 0
  case shutdown = 1
  case booting = 2
  case booted = 3
  case shuttingDown = 4
  case DFU = 5
  case recovery = 6
  case restoreOS = 7
  case unknown = 99
}

/// Represents the kind of a target.
@objc public enum FBiOSTargetType: UInt {
  case none = 0
  case simulator = 1
  case device = 2
  case localMac = 4
}

/// String representations of FBiOSTargetState.
public struct FBiOSTargetStateString: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let creating = FBiOSTargetStateString(rawValue: "Creating")
  public static let shutdown = FBiOSTargetStateString(rawValue: "Shutdown")
  public static let booting = FBiOSTargetStateString(rawValue: "Booting")
  public static let booted = FBiOSTargetStateString(rawValue: "Booted")
  public static let shuttingDown = FBiOSTargetStateString(rawValue: "Shutting Down")
  public static let DFU = FBiOSTargetStateString(rawValue: "DFU")
  public static let recovery = FBiOSTargetStateString(rawValue: "Recovery")
  public static let restoreOS = FBiOSTargetStateString(rawValue: "RestoreOS")
  public static let unknown = FBiOSTargetStateString(rawValue: "Unknown")
}
