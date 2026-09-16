/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


@preconcurrency import CoreSimulator
@preconcurrency import TapTapTapCore
@preconcurrency import Foundation

extension FBSimulatorConfiguration {

  // MARK: - Matching Configuration against Available Versions

  public class func newestAvailableOS(forDevice device: FBDeviceType) throws -> FBOSVersion? {
    try osVersions(forRuntimes: supportedRuntimes(forDevice: device)).last
  }

  // MARK: - Inference

  @objc(inferSimulatorConfigurationFromDevice:error:)
  public class func inferSimulatorConfiguration(fromDevice simDevice: SimDevice) throws -> FBSimulatorConfiguration {
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    guard FBiOSTargetConfiguration.nameToOSVersion[osName] != nil else {
      throw FBSimulatorConfigurationError.unsupportedOSVersion(name: osName.rawValue)
    }
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    guard FBiOSTargetConfiguration.nameToDevice[model] != nil else {
      throw FBSimulatorConfigurationError.unsupportedDevice(name: model.rawValue)
    }
    return try FBSimulatorConfiguration.defaultConfiguration().withOSNamed(osName).withDeviceModel(model)
  }

  @objc(inferSimulatorConfigurationFromDeviceSynthesizingMissing:)
  public class func inferSimulatorConfigurationFromDeviceSynthesizingMissing(_ simDevice: SimDevice) -> FBSimulatorConfiguration {
    if let configuration = try? inferSimulatorConfiguration(fromDevice: simDevice) {
      return configuration
    }
    // Synthesize directly rather than via the throwing `defaultConfiguration()`: this path must not
    // fail (non-throwing FBSimulator init) and it overrides both OS and device anyway.
    let osName = FBOSVersionName(rawValue: simDevice.runtime.name!)
    let model = FBDeviceModel(rawValue: simDevice.deviceType.name!)
    let os = FBiOSTargetConfiguration.nameToOSVersion[osName] ?? FBOSVersion.generic(withName: osName.rawValue)
    let device = FBiOSTargetConfiguration.nameToDevice[model] ?? FBDeviceType.generic(withName: model.rawValue)
    return FBSimulatorConfiguration(device: device, os: os).withDeviceModel(model)
  }

  // MARK: - Private

  private class func osVersions(forRuntimes runtimes: [SimRuntime]) -> [FBOSVersion] {
    runtimes.map { runtime in
      let name = FBOSVersionName(rawValue: runtime.name!)
      return FBiOSTargetConfiguration.nameToOSVersion[name] ?? FBOSVersion.generic(withName: runtime.name!)
    }
  }

  private class func supportedRuntimes(forDevice device: FBDeviceType) throws -> [SimRuntime] {
    try FBSimulatorServiceContext.sharedServiceContext().supportedRuntimes()
      .filter { runtime in
        (runtime.supportedProductFamilyIDs as! [NSNumber]).contains(NSNumber(value: device.family.rawValue))
      }
      .sorted { left, right in
        let leftVersion = NSDecimalNumber(string: left.versionString)
        let rightVersion = NSDecimalNumber(string: right.versionString)
        return leftVersion.compare(rightVersion) == .orderedAscending
      }
  }
}
