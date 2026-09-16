/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


import Foundation

/// Keys for accessibility element dictionaries.
///
/// The raw values are the on-the-wire JSON keys of `describe-ui` and must not change.
public enum FBAXKeys: String, Sendable {
  case label = "AXLabel"
  case frame = "AXFrame"
  case value = "AXValue"
  case uniqueID = "AXUniqueId"
  case type = "type"
  case title = "title"
  case frameDict = "frame"
  case help = "help"
  case enabled = "enabled"
  case customActions = "custom_actions"
  case role = "role"
  case roleDescription = "role_description"
  case subrole = "subrole"
  case contentRequired = "content_required"
  case pid = "pid"
  /// Part of the public output schema; not requested from the simulator (see AXe AccessibilityFetcher).
  case traits = "traits"
}
