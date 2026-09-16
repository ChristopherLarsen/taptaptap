/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import TapTapTapCore
@preconcurrency import Foundation

extension FBSimulator {

  public func connectToFramebuffer() async throws -> FBFramebuffer {
    try await lifecycleCommands().connectToFramebufferAsync()
  }
}

@objc(FBSimulatorLifecycleCommands)
public final class FBSimulatorLifecycleCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var hid: FBSimulatorHID?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLifecycleCommands {
    FBSimulatorLifecycleCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Async

  fileprivate func connectToFramebufferAsync() async throws -> FBFramebuffer {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    return try FBFramebuffer.mainScreenSurface(for: simulator, logger: simulator.logger!)
  }

  fileprivate func connectToHIDAsync() async throws -> FBSimulatorHID {
    if let hid = self.hid {
      return hid
    }
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let hid = try FBSimulatorHID(for: simulator)
    self.hid = hid
    return hid
  }
}

extension FBSimulator: AsyncSimulatorLifecycleCommands {

  public func connectToHID() async throws -> FBSimulatorHID {
    try await lifecycleCommands().connectToHIDAsync()
  }
}
