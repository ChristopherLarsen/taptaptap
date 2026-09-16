/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import Foundation

/// Request options for serializing an accessibility element tree.
public struct FBAccessibilityRequestOptions: Sendable {

  /// If `true`, data is returned in nested format with `children`; otherwise a flat array (each
  /// element serialized independently, in traversal order). Matches idb's `--nested` semantics:
  /// idb's own default is flat. Default: `false`.
  public var nestedFormat: Bool

  /// Keys to include for each element.
  public var keys: Set<FBAXKeys>

  public init(nestedFormat: Bool = false, keys: Set<FBAXKeys>) {
    self.nestedFormat = nestedFormat
    self.keys = keys
  }
}
