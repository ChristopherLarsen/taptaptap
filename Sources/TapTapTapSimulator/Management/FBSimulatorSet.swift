/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import TapTapTapCore
import Foundation

@objc(FBSimulatorSet)
public final class FBSimulatorSet: NSObject {

  // MARK: - Properties

  @objc public let configuration: FBSimulatorControlConfiguration
  @objc public let deviceSet: SimDeviceSet
  @objc public let logger: (any FBControlCoreLogger)?
  @objc public let reporter: (any FBEventReporter)?
  @objc public let workQueue: DispatchQueue
  @objc public let asyncQueue: DispatchQueue

  private var _allSimulators: [FBSimulator]
  private var inflationStrategy: FBSimulatorInflationStrategy!

  // MARK: - Initializers

  @objc(setWithConfiguration:deviceSet:logger:reporter:)
  public class func set(withConfiguration configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) -> FBSimulatorSet {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    return FBSimulatorSet(configuration: configuration, deviceSet: deviceSet, logger: logger, reporter: reporter)
  }

  private init(configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) {
    self.configuration = configuration
    self.deviceSet = deviceSet
    self.logger = logger
    self.reporter = reporter
    self.workQueue = DispatchQueue.main
    self.asyncQueue = DispatchQueue.global(qos: .default)
    self._allSimulators = []
    super.init()
    self.inflationStrategy = FBSimulatorInflationStrategy.strategy(for: self)
  }

  // MARK: - NSObject

  public override var description: String {
    FBCollectionInformation.oneLineDescription(from: allSimulators)
  }

  // MARK: - Public Properties

  @objc
  public var allSimulators: [FBSimulator] {
    _allSimulators = inflationStrategy.inflate(
      fromDevices: deviceSet.availableDevices,
      exitingSimulators: _allSimulators
    )
    .sorted { ($0 as FBSimulator).compare($1 as any FBiOSTarget) == .orderedAscending }
    return _allSimulators
  }
}
