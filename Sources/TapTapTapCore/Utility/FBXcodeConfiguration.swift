/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBXcodeConfiguration)
public class FBXcodeConfiguration: NSObject {

  // MARK: Public Properties

  @objc public static let developerDirectory: String = {
    (try? FBXcodeDirectory.resolveDeveloperDirectory()) ?? ""
  }()

  // MARK: NSObject

  override public class func description() -> String {
    "Developer Directory \(developerDirectory)"
  }

  public override var description: String {
    Self.description()
  }
}
