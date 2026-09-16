/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreSimulator
import TapTapTapCore
import Foundation

/// An implementation of FBiOSTarget for iOS Simulators.
/// Command members are implemented in Swift extensions on FBSimulator.
public final class FBSimulator: NSObject, FBiOSTarget {

  /// The Underlying SimDevice.
  public let device: SimDevice

  /// The FBSimulatorConfiguration representing this Simulator.
  public let configuration: FBSimulatorConfiguration

  /// The Simulator Set that the Simulator belongs to.
  public private(set) weak var set: FBSimulatorSet?

  /// Per-simulator cache of command objects.
  public let commandCache = FBTargetCommandCache()

  public let logger: (any FBControlCoreLogger)?

  public class func fromSimDevice(_ device: SimDevice, configuration: FBSimulatorConfiguration?, set: FBSimulatorSet) -> FBSimulator {
    FBSimulator(
      device: device,
      configuration: configuration ?? FBSimulatorConfiguration.inferSimulatorConfigurationFromDeviceSynthesizingMissing(device),
      set: set,
      logger: set.logger)
  }

  private init(device: SimDevice, configuration: FBSimulatorConfiguration, set: FBSimulatorSet, logger: (any FBControlCoreLogger)?) {
    self.device = device
    // The ObjC original stored a copy of the (immutable) configuration.
    self.configuration = configuration.copy() as! FBSimulatorConfiguration
    self.set = set
    self.logger = logger?.withName(device.udid.uuidString)
    super.init()
  }

  // MARK: FBiOSTargetInfo / FBiOSTarget

  public var udid: String {
    device.udid.uuidString
  }

  public var name: String {
    device.name
  }

  public var state: FBiOSTargetState {
    FBiOSTargetState(rawValue: UInt(device.state)) ?? .unknown
  }

  public var targetType: FBiOSTargetType {
    .simulator
  }

  public var deviceType: FBDeviceType {
    configuration.device
  }

  public var osVersion: FBOSVersion {
    configuration.os
  }

  public var workQueue: DispatchQueue {
    DispatchQueue.main
  }

  public func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    FBiOSTargetComparison(self, target)
  }

  // MARK: NSObject

  public override var hash: Int {
    device.hash
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let simulator = object as? FBSimulator else {
      return false
    }
    return device.isEqual(simulator.device)
  }

  public override var description: String {
    FBiOSTargetDescribe(self) as String
  }
}
