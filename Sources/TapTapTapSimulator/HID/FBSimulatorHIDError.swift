/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// The failure cases of the HID layer.
///
/// Previously these were stringly-typed `FBSimulatorError` `NSError`s. No consumer inspects their
/// domain or code — they are surfaced only as messages — so they are modelled here as a typed enum
/// that enumerates the failure modes. `errorDescription` reproduces the original message strings
/// verbatim, so the text surfaced to callers is unchanged.
public enum FBSimulatorHIDError: Error, LocalizedError {
  /// The runtime-only `SimDeviceLegacyHIDClient` class could not be looked up by name.
  case clientClassUnavailable(className: String)
  /// The HID client class was found but `initWithDevice:error:` returned nil.
  case clientCreationFailed(clientClass: String, underlying: Error?)
  /// The SimulatorKit framework executable could not be opened.
  case simulatorKitUnavailable
  /// The legacy keyboard HID service is suppressed because `dtuhidd` is active (Xcode 27+).
  case keyboardSuppressedByActiveDTUHIDD
  /// A primitive is not (yet) implemented on the DTUHID transport.
  case notImplementedOnDTUHIDTransport(operation: String)
  /// The `dtuhidd` digitizer service could not be looked up in the simulator's bootstrap namespace.
  case dtuhidDigitizerServiceUnavailable(underlying: Error?)
  /// The private `_4sim` XPC endpoint symbols could not be resolved (older toolchain).
  case dtuhidXPCSymbolsUnavailable
  /// The `dtuhidd` host XPC connection could not be created.
  case dtuhidConnectionFailed
  /// SimulatorKit returned an Indigo touch message smaller than the offsets taptaptap patches.
  case indigoMessageTooSmall(size: Int, required: Int)

  public var errorDescription: String? {
    switch self {
    case let .clientClassUnavailable(className):
      return "Could not look up class \(className)"
    case let .clientCreationFailed(clientClass, _):
      return "Could not create instance of \(clientClass)"
    case .simulatorKitUnavailable:
      return "Could not open the SimulatorKit framework executable"
    case .keyboardSuppressedByActiveDTUHIDD:
      return
        "Keyboard HID is suppressed because dtuhidd is active (Device Hub is open, or a CoreDevice HID client attached). Boot a fresh simulator with Device Hub closed, or use the CoreDevice HID transport. (Xcode 27 / CoreSimulator-1155.4)"
    case let .notImplementedOnDTUHIDTransport(operation):
      return "\(operation) is not implemented on the DTUHID transport"
    case .dtuhidDigitizerServiceUnavailable:
      return "Could not look up the dtuhidd digitizer service (com.apple.coredevice.feature.remote.hid.digitizer)"
    case .dtuhidXPCSymbolsUnavailable:
      return "Could not resolve the private _4sim XPC endpoint symbols required for the DTUHID transport"
    case .dtuhidConnectionFailed:
      return "Could not create the dtuhidd host XPC connection"
    case let .indigoMessageTooSmall(size, required):
      return "SimulatorKit returned a \(size)-byte Indigo touch message; at least \(required) bytes are required"
    }
  }
}
