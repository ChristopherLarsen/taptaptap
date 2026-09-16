/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let FBControlCoreStderrLogging = "FBCONTROLCORE_LOGGING"
public let FBControlCoreDebugLogging = "FBCONTROLCORE_DEBUG_LOGGING"


@objc(FBControlCoreGlobalConfiguration)
public class FBControlCoreGlobalConfiguration: NSObject {

  nonisolated(unsafe) private static var _logger: (any FBControlCoreLogger)?

  // MARK: Logger

  @objc public class var defaultLogger: any FBControlCoreLogger {
    get {
      if let existing = _logger { return existing }
      let created = createDefaultLogger()
      _logger = created
      return created
    }
    set {
      if _logger != nil {
        newValue.debug().log("Overriding the Default Logger with \(newValue)")
      }
      _logger = newValue
    }
  }

  // MARK: NSObject

  override public class func description() -> String {
    "Default Logger \(_logger.map(String.init(describing:)) ?? "(nil)")"
  }

  public override var description: String {
    Self.description()
  }

  // MARK: Private

  private class func createDefaultLogger() -> any FBControlCoreLogger {
    FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: stderrLoggingEnabledByDefault, withDebugLogging: debugLoggingEnabledByDefault)
  }

  private class var stderrLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] else { return false }
    return (value as NSString).boolValue
  }

  private class var debugLoggingEnabledByDefault: Bool {
    guard let value = ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] else { return false }
    return (value as NSString).boolValue
  }
}
