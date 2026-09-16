/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import Foundation

/// Serialized accessibility elements: an `NSArray` (frontmost application) or an
/// `NSDictionary` (single element at a point), in the nested format with `children`.
public struct FBAccessibilityElementsResponse {

  public let elements: Any

  public init(elements: Any) {
    self.elements = elements
  }
}
