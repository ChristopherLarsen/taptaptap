/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Screenshot formats (taptaptap 3e: Swift port of the FBScreenshotCommands.h NS_STRING_ENUM).
public struct FBScreenshotFormat: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let jpeg = FBScreenshotFormat(rawValue: "jpeg")
  public static let png = FBScreenshotFormat(rawValue: "png")
}
