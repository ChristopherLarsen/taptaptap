/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetCommand Protocol

/// A protocol that defines a command class that can be instantiated for a target.
/// Concrete command classes (e.g. `FBSimulatorApplicationCommands`) adopt this directly.
@objc public protocol FBiOSTargetCommand: NSObjectProtocol {
  /// Instantiates the Commands instance.
  @objc(commandsWithTarget:)
  static func commands(with target: any FBiOSTarget) -> Self
}

// MARK: - FBiOSTargetInfo Protocol

/// A protocol that defines an informational target.
@objc public protocol FBiOSTargetInfo: NSObjectProtocol {

  /// The UDID of the target.
  var udid: String { get }

  /// The name of the target.
  var name: String { get }

  /// The device type of the target.
  var deviceType: FBDeviceType { get }

  /// The OS version of the target.
  var osVersion: FBOSVersion { get }

  /// The type of the target.
  var targetType: FBiOSTargetType { get }

  /// The state of the target.
  var state: FBiOSTargetState { get }
}

// MARK: - FBiOSTarget Protocol

@objc public protocol FBiOSTarget: NSObjectProtocol, FBiOSTargetInfo {

  /// The logger to log to.
  var logger: (any FBControlCoreLogger)? { get }

  /// The queue on which target work is serialized.
  var workQueue: DispatchQueue { get }

  /// Target comparison, used for sorting.
  @objc(compare:)
  func compare(_ target: any FBiOSTarget) -> ComparisonResult
}

// MARK: - Target helpers

/// The canonical string representation of the state enum.
public func FBiOSTargetStateStringFromState(_ state: FBiOSTargetState) -> FBiOSTargetStateString {
  switch state {
  case .creating:
    return .creating
  case .shutdown:
    return .shutdown
  case .booting:
    return .booting
  case .booted:
    return .booted
  case .shuttingDown:
    return .shuttingDown
  case .DFU:
    return .DFU
  case .recovery:
    return .recovery
  case .restoreOS:
    return .restoreOS
  case .unknown:
    return .unknown
  }
}

/// The canonical enum representation of the state string.
public func FBiOSTargetComparison(_ left: FBiOSTarget, _ right: FBiOSTarget) -> ComparisonResult {
  var comparison = NSNumber(value: left.targetType.rawValue).compare(NSNumber(value: right.targetType.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  comparison = left.osVersion.number.compare(right.osVersion.number)
  if comparison != .orderedSame {
    return comparison
  }
  comparison = NSNumber(value: left.deviceType.family.rawValue).compare(NSNumber(value: right.deviceType.family.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  comparison = left.deviceType.model.rawValue.compare(right.deviceType.model.rawValue)
  if comparison != .orderedSame {
    return comparison
  }
  comparison = NSNumber(value: left.state.rawValue).compare(NSNumber(value: right.state.rawValue))
  if comparison != .orderedSame {
    return comparison
  }
  return left.udid.compare(right.udid)
}

/// Constructs a string description of the provided target.
public func FBiOSTargetDescribe(_ target: FBiOSTargetInfo) -> NSString {
  return "\(target.udid) | \(target.name) | \(FBiOSTargetStateStringFromState(target.state).rawValue) | \(target.deviceType.model.rawValue) | \(target.osVersion) " as NSString
}


/// Constructs an NSPredicate matching the specified UDIDs.
public func FBiOSTargetPredicateForUDIDs(_ udids: [String]) -> NSPredicate {
  let udidsSet = Set(udids)
  return NSPredicate { (evaluatedObject, _) -> Bool in
    guard let candidate = evaluatedObject as? FBiOSTarget else {
      return false
    }
    return udidsSet.contains(candidate.udid)
  }
}
