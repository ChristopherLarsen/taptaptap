/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Known instruction set architectures (taptaptap 3e: Swift port of the FBArchitecture.h NS_STRING_ENUM).
public struct FBArchitecture: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let I386 = FBArchitecture(rawValue: "i386")
  public static let X86_64 = FBArchitecture(rawValue: "x86_64")
  public static let armv7 = FBArchitecture(rawValue: "armv7")
  public static let armv7s = FBArchitecture(rawValue: "armv7s")
  public static let arm64 = FBArchitecture(rawValue: "arm64")
  public static let arm64e = FBArchitecture(rawValue: "arm64e")
}
