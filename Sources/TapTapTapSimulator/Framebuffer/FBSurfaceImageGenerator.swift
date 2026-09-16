/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import TapTapTapCore
import Foundation
import IOSurface

@objc(FBSurfaceImageGenerator)
public final class FBSurfaceImageGenerator: NSObject, FBFramebufferConsumer {

  // MARK: - Properties

  private let logger: (any FBControlCoreLogger)?
  private var surface: IOSurface?

  // MARK: - Initializers

  @objc(imageGeneratorWithPurpose:logger:)
  public init(purpose: String, logger: (any FBControlCoreLogger)?) {
    self.logger = logger?.withName("\(logger?.name ?? "")_\(purpose)")
    super.init()
  }

  // MARK: - Public

  @objc
  public func image() -> CGImage? {
    guard let surface = self.surface else {
      return nil
    }
    let context = CIContext(options: nil)
    let ciImage = CIImage(ioSurface: unsafeBitCast(surface, to: IOSurfaceRef.self))
    return context.createCGImage(ciImage, from: ciImage.extent)
  }

  // MARK: - FBFramebufferConsumer

  @objc
  public func didChange(_ surface: IOSurface?) {
    if let oldSurface = self.surface {
      logger?.info().log("Removing old surface \(oldSurface)")
      oldSurface.decrementUseCount()
      self.surface = nil
    }
    if let surface {
      surface.incrementUseCount()
      logger?.info().log("Received IOSurface from Framebuffer Service \(surface)")
      self.surface = surface
    }
  }

  @objc
  public func didReceiveDamageRect() {
  }
}
