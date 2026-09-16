/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import TapTapTapCore
import Foundation

extension FBSimulator {

  func screenshotCommands() throws -> FBSimulatorScreenshotCommands {
    commandCache.resolve { FBSimulatorScreenshotCommands.commands(with: self) }
  }

  func launchCtlCommands() throws -> FBSimulatorLaunchCtlCommands {
    commandCache.resolve { FBSimulatorLaunchCtlCommands.commands(with: self) }
  }

  func lifecycleCommands() throws -> FBSimulatorLifecycleCommands {
    commandCache.resolve { FBSimulatorLifecycleCommands.commands(with: self) }
  }

  func accessibilityCommands() throws -> FBSimulatorAccessibilityCommands {
    commandCache.resolve { FBSimulatorAccessibilityCommands.commands(with: self) }
  }
}
