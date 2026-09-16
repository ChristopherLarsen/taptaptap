/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown while resolving a `FBSimulatorConfiguration` against the runtimes and device types
/// available from CoreSimulator.
///
/// Typed cases let callers pattern-match, while `LocalizedError.errorDescription` preserves the
/// human-readable messages that flow through `error.localizedDescription`. Underlying failures are
/// captured as their localized message rather than the error object, keeping the enum a `Sendable`
/// value type.
public enum FBSimulatorConfigurationError: LocalizedError, Sendable {

  /// The OS version name is not registered with FBSimulatorControl.
  case unsupportedOSVersion(name: String)

  /// The device model is not registered with FBSimulatorControl.
  case unsupportedDevice(name: String)

  /// The device type backing the default configuration is not registered.
  case noDefaultDeviceTypeRegistered(model: String)

  /// No OS versions are available for the default configuration.
  case noAvailableOSVersionsForDefault

  public var errorDescription: String? {
    switch self {
    case .unsupportedOSVersion(let name):
      return "Could not obtain OS Version for \(name), perhaps it is unsupported by FBSimulatorControl"
    case .unsupportedDevice(let name):
      return "Could not obtain Device for \(name), perhaps it is unsupported by FBSimulatorControl"
    case .noDefaultDeviceTypeRegistered(let model):
      return "No device type is registered for '\(model)'"
    case .noAvailableOSVersionsForDefault:
      return "No available OS versions for the default simulator configuration"
    }
  }
}

extension FBSimulatorConfigurationError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs surface the
  /// human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "FBSimulatorConfigurationError" }
}
