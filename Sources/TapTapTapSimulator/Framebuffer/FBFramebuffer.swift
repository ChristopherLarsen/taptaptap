/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ObjCExceptionGuard
@preconcurrency import CoreSimDeviceIO
@preconcurrency import CoreSimulator
@preconcurrency import TapTapTapCore
import Foundation
import IOSurface

@objc public protocol FBFramebufferConsumer: NSObjectProtocol {
  @objc(didChangeIOSurface:)
  func didChange(_ surface: IOSurface?)

  func didReceiveDamageRect()
}

@objc(FBFramebuffer)
public final class FBFramebuffer: NSObject, @unchecked Sendable {

  // MARK: - Properties

  private let consumers: NSMapTable<AnyObject, NSUUID>
  private let logger: any FBControlCoreLogger
  private let surface: AnyObject // SimDisplayIOSurfaceRenderable & SimDisplayRenderable


  // MARK: - Initializers

  @objc(mainScreenSurfaceForSimulator:logger:error:)
  public class func mainScreenSurface(for simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> FBFramebuffer {
    let ioClient = simulator.device.io!
    let ports: [Any]? = ioClient.ioPorts()
    guard let ports else {
      throw FBSimulatorError.describe("No IO ports available on \(ioClient)").build()
    }
    for port in ports {
      guard let portInterface = port as? SimDeviceIOPortInterface else {
        continue
      }
      let descriptor = portInterface.descriptor as AnyObject
      guard descriptor.conforms(to: SimDisplayRenderable.self),
        descriptor.conforms(to: SimDisplayIOSurfaceRenderable.self)
      else {
        continue
      }
      guard descriptor.responds(to: NSSelectorFromString("state")) else {
        logger.log("SimDisplay \(descriptor) does not have a state, cannot determine if it is the main display")
        continue
      }
      let descriptorState = descriptor.perform(NSSelectorFromString("state"))?.takeUnretainedValue() as! SimDisplayDescriptorState
      let displayClass = descriptorState.displayClass
      if displayClass != 0 {
        logger.log("SimDisplay Class is '\(displayClass)' which is not the main display '0'")
        continue
      }
      return FBFramebuffer(surface: descriptor, logger: logger)
    }
    throw FBSimulatorError.describe("Could not find the Main Screen Surface for Clients \(FBCollectionInformation.oneLineDescription(from: ports)) in \(ioClient)").build()
  }

  private init(surface: AnyObject, logger: any FBControlCoreLogger) {
    self.consumers = NSMapTable(keyOptions: .weakMemory, valueOptions: .copyIn)
    self.logger = logger
    self.surface = surface
    super.init()
  }

  // MARK: - Public Methods

  @objc(attachConsumer:onQueue:)
  public func attach(_ consumer: any FBFramebufferConsumer, on queue: DispatchQueue) -> IOSurface? {
    // Don't attach the same consumer twice
    assert(!isConsumerAttached(consumer), "Cannot re-attach the same consumer \(consumer)")
    let consumerUUID = NSUUID()

    // Attempt to return the surface synchronously (if supported).
    let immediateSurface = extractImmediatelyAvailableSurface()

    // Register the consumer.
    consumers.setObject(consumerUUID, forKey: consumer as AnyObject)
    registerConsumer(consumer, uuid: consumerUUID, queue: queue)

    return immediateSurface
  }

  @objc(isConsumerAttached:)
  public func isConsumerAttached(_ consumer: any FBFramebufferConsumer) -> Bool {
    let enumerator = consumers.keyEnumerator()
    while let existingConsumer = enumerator.nextObject() {
      if existingConsumer as AnyObject === consumer as AnyObject {
        return true
      }
    }
    return false
  }

  // MARK: - Private

  private func extractImmediatelyAvailableSurface() -> IOSurface? {
    guard let renderable = surface as? SimDisplayIOSurfaceRenderable else {
      return nil
    }
    if let surface = try? FBObjCExceptionGuard.guarded({ renderable.framebufferSurface }) as? IOSurface {
      return surface
    }
    return try? FBObjCExceptionGuard.guarded({ renderable.ioSurface }) as? IOSurface
  }

  private func registerConsumer(_ consumer: any FBFramebufferConsumer, uuid: NSUUID, queue: DispatchQueue) {
    let renderable = surface as! SimDisplayIOSurfaceRenderable
    nonisolated(unsafe) let consumerRef = consumer

    let ioSurfaceChanged: (Any?) -> Void = { [weak self] surfaceArg in
      guard let self else { return }
      nonisolated(unsafe) let surfaceRef = surfaceArg
      queue.async {
        consumerRef.didChange(surfaceRef as? IOSurface)
      }
    }

    _ = try? FBObjCExceptionGuard.guarded {
      renderable.registerCallback(with: uuid as UUID, ioSurfacesChangeCallback: ioSurfaceChanged)
    }
    _ = try? FBObjCExceptionGuard.guarded {
      renderable.registerCallback(with: uuid as UUID, ioSurfaceChangeCallback: ioSurfaceChanged)
    }

    let displayRenderable = surface as! SimDisplayRenderable
    let damageCallback: ([Any]?) -> Void = { [weak self] _ in
      guard self != nil else { return }
      queue.async {
        consumerRef.didReceiveDamageRect()
      }
    }
    _ = try? FBObjCExceptionGuard.guarded {
      displayRenderable.registerCallback(with: uuid as UUID, damageRectanglesCallback: damageCallback)
    }
  }

}
