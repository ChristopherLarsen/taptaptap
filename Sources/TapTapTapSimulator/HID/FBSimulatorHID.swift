/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import TapTapTapCore
import Foundation

/**
 The HID abstraction layer for a Simulator. Touch, button and keyboard events are delivered through
 a pluggable `FBSimulatorHIDTransport`: DTUHID (dtuhidd, Xcode 27+) or the legacy Indigo
 `SimDeviceLegacyHIDClient`. Transport sends are serialized, so the type is `@unchecked Sendable`.
 */
public final class FBSimulatorHID: CustomStringConvertible, @unchecked Sendable {

  /// Default Mach send timeout (in milliseconds) for the `sendPurpleEvent:` convenience wrapper.
  /// Healthy round-trips return in low single-digit milliseconds; 2000ms absorbs scheduler jitter
  /// while bounding the wedge condition where SpringBoard's PurpleWorkspacePort receive queue fills.

  // MARK: Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: FBSimulatorHIDTransport
  /// The Purple/GSEvent payload builder (orientation, lock).

  private weak var simulator: FBSimulator?
  /// The transport selected for touch, button, and keyboard primitives.
  public let transportType: FBSimulatorHIDTransportType

  // MARK: Initializers

  /**
   Creates a `FBSimulatorHID` for the provided Simulator.

   `transport` selects the HID path. When `nil` (the default) it is resolved with
   `FBSimulator.defaultHIDTransport` — the DTUHID transport when an active `dtuhidd` has suppressed
   the legacy HID, and the legacy Indigo path otherwise — so a caller that does not care gets a
   working transport without choosing one. Pass an explicit value to force a specific transport. Will
   fail if the chosen transport cannot be established for the provided Simulator (registration may
   need to occur prior to booting).
   */
  public convenience init(
    for simulator: FBSimulator, transport transportType: FBSimulatorHIDTransportType? = nil
  ) throws {
    let resolvedTransportType = transportType ?? simulator.defaultHIDTransport
    let transport: FBSimulatorHIDTransport
    switch resolvedTransportType {
    case .indigo:
      transport = try FBSimulatorIndigoHIDTransport.indigo(for: simulator)
    case .dtuhid:
      transport = try FBSimulatorDTUHIDTransport.dtuhid(for: simulator)
    }
    self.init(transport: transport, transportType: resolvedTransportType, simulator: simulator)
  }

  private init(transport: FBSimulatorHIDTransport, transportType: FBSimulatorHIDTransportType, simulator: FBSimulator) {
    self.transport = transport
    self.transportType = transportType
    self.simulator = simulator
  }

  // MARK: Lifecycle

  /**
   Disconnects from the remote HID.
   */
  public func disconnect() {
    transport.disconnect()
  }

  // MARK: Indigo Event Send Primitives

  /// Sends a single-finger touch at the given point (in points).
  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    try await transport.sendTouch(direction: direction, x: x, y: y)
  }

  /// Sends a two-finger touch (for multi-touch gestures) at the given points (in points).
  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    try await transport.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
  }

  /// Sends a hardware button event.
  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    try await transport.sendButton(direction: direction, button: button)
  }

  /// Sends a keyboard key event.
  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    try await transport.sendKeyboard(direction: direction, keyCode: keyCode)
  }

  /// Drains the transport once a gesture's primitives have all been sent (see
  /// `FBSimulatorHIDTransport.flush`). `FBSimulatorHIDEvent.send(on:logger:)` calls this once per
  /// dispatched event; the individual `send*` primitives do not.
  func flush() async throws {
    try await transport.flush()
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "SimulatorKit HID"
  }
}
