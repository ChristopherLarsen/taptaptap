/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

/// A Protocol for Classes that receive Logger Messages.
@objc public protocol FBControlCoreLogger: NSObjectProtocol {
  /// Logs a Message with the provided String.
  @discardableResult
  func log(_ message: String) -> FBControlCoreLogger

  /// Returns the Info Logger variant.
  func info() -> FBControlCoreLogger

  /// Returns the Debug Logger variant.
  func debug() -> FBControlCoreLogger

  /// Returns the Error Logger variant.
  func error() -> FBControlCoreLogger

  /// Returns a Logger for a named 'facility' or 'tag'.
  func withName(_ name: String) -> FBControlCoreLogger

  /// Enables or Disables date formatting in the logger.
  func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger

  /// The Prefix for the Logger, if set.
  var name: String? { get }

  /// The Current Log Level.
  var level: FBControlCoreLogLevel { get }
}

// MARK: - Log level

/// The Log Level.
/// The Multiple Level exists so that composite loggers can decide whether to log individually.
@objc public enum FBControlCoreLogLevel: UInt {
  case error = 1
  case info = 2
  case debug = 3
  case multiple = 1000
}

// MARK: - Implementations
// taptaptap 3e: Swift port of FBControlCoreLogger.m and FBControlCoreLogger+OSLog.m.

/// A composite logger that logs to many loggers.
open class FBCompositeLogger: NSObject, FBControlCoreLogger {

  /// The loggers to log to.
  public let loggers: [FBControlCoreLogger]

  public required init(loggers: [FBControlCoreLogger]) {
    self.loggers = loggers
    super.init()
  }

  // Designated (not convenience) so subclasses such as AxeLogger can override it.
  public override init() {
    self.loggers = []
    super.init()
  }

  @discardableResult
  public func log(_ message: String) -> FBControlCoreLogger {
    guard let line = FBControlCoreLoggerFactory.loggableStringLine(message) else {
      return self
    }
    for logger in loggers {
      logger.log(line)
    }
    return self
  }

  // Each variant applies the same transformation to every child and wraps the results in a new
  // instance of the receiver's class (the ObjC original used performSelector: with _cmd).
  public func info() -> FBControlCoreLogger {
    type(of: self).init(loggers: loggers.map { $0.info() })
  }

  public func debug() -> FBControlCoreLogger {
    type(of: self).init(loggers: loggers.map { $0.debug() })
  }

  public func error() -> FBControlCoreLogger {
    type(of: self).init(loggers: loggers.map { $0.error() })
  }

  public func withName(_ name: String) -> FBControlCoreLogger {
    type(of: self).init(loggers: loggers.map { $0.withName(name) })
  }

  public func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    type(of: self).init(loggers: loggers.map { $0.withDateFormatEnabled(enabled) })
  }

  public var name: String? {
    nil
  }

  public var level: FBControlCoreLogLevel {
    .multiple
  }
}

/// Writes each message as one line straight to a file descriptor.
private final class FBFileDescriptorLogger: NSObject, FBControlCoreLogger {
  // Serializes writes across every instance, as @synchronized(class) did.
  private static let writeLock = NSLock()

  private let fileDescriptor: Int32
  private let dateFormatter: DateFormatter?
  let name: String?
  // The ObjC original never assigned its level ivar (it stayed 0, which is no case); nothing reads
  // a logger's level, so report the level-neutral value.
  let level: FBControlCoreLogLevel = .multiple

  init(fileDescriptor: Int32, name: String?, dateFormatter: DateFormatter?) {
    self.fileDescriptor = fileDescriptor
    self.name = name
    self.dateFormatter = dateFormatter
    super.init()
  }

  @discardableResult
  func log(_ message: String) -> FBControlCoreLogger {
    guard let line = FBControlCoreLoggerFactory.loggableStringLine(message) else {
      return self
    }
    var string = ""
    if let dateFormatter {
      string += "\(dateFormatter.string(from: Date())) "
    }
    if let name {
      string += "[\(name)] "
    }
    string += line
    string += "\n"
    let bytes = Array(string.utf8)
    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }
    bytes.withUnsafeBufferPointer { buffer in
      var offset = 0
      while offset < buffer.count {
        let written = write(fileDescriptor, buffer.baseAddress! + offset, buffer.count - offset)
        if written < 0 {
          if errno == EINTR {
            continue
          }
          break
        }
        offset += written
      }
    }
    return self
  }

  func info() -> FBControlCoreLogger {
    FBFileDescriptorLogger(fileDescriptor: fileDescriptor, name: name, dateFormatter: dateFormatter)
  }

  func debug() -> FBControlCoreLogger {
    FBFileDescriptorLogger(fileDescriptor: fileDescriptor, name: name, dateFormatter: dateFormatter)
  }

  func error() -> FBControlCoreLogger {
    FBFileDescriptorLogger(fileDescriptor: fileDescriptor, name: name, dateFormatter: dateFormatter)
  }

  func withName(_ name: String) -> FBControlCoreLogger {
    FBFileDescriptorLogger(fileDescriptor: fileDescriptor, name: name, dateFormatter: dateFormatter)
  }

  func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    var formatter: DateFormatter?
    if enabled {
      formatter = DateFormatter()
      formatter?.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZZZ"
    }
    return FBFileDescriptorLogger(fileDescriptor: fileDescriptor, name: name, dateFormatter: formatter)
  }
}

/// A logger on top of os_log.
private final class FBOSLogLogger: NSObject, FBControlCoreLogger {
  static let subsystem = "com.taptaptap.core"

  private let client: OSLog
  let name: String?
  let level: FBControlCoreLogLevel

  init(client: OSLog, name: String?, level: FBControlCoreLogLevel) {
    self.client = client
    self.name = name
    self.level = level
    super.init()
  }

  @discardableResult
  func log(_ message: String) -> FBControlCoreLogger {
    let type: OSLogType
    switch level {
    case .error:
      type = .error
    case .info:
      type = .info
    case .debug:
      type = .debug
    case .multiple:
      type = .default
    }
    os_log("%{public}@", log: client, type: type, message)
    return self
  }

  func info() -> FBControlCoreLogger {
    FBOSLogLogger(client: client, name: name, level: .info)
  }

  func debug() -> FBControlCoreLogger {
    FBOSLogLogger(client: client, name: name, level: .debug)
  }

  func error() -> FBControlCoreLogger {
    FBOSLogLogger(client: client, name: name, level: .error)
  }

  func withName(_ name: String) -> FBControlCoreLogger {
    FBOSLogLogger(client: OSLog(subsystem: Self.subsystem, category: name), name: name, level: level)
  }

  func withDateFormatEnabled(_ enabled: Bool) -> FBControlCoreLogger {
    self
  }
}

/// Implementations of Loggers.
public final class FBControlCoreLoggerFactory: NSObject {

  /// A logger that logs using os_log, optionally mirrored to stderr.
  /// The ObjC original fell back to an NSLog logger when os_log was unavailable (non-Apple clang
  /// builds); os_log is always available here, so that fallback is gone.
  public static func systemLoggerWriting(toStderr writeToStdErr: Bool, withDebugLogging debugLogging: Bool) -> FBControlCoreLogger {
    let systemLogger = FBOSLogLogger(
      client: OSLog(subsystem: FBOSLogLogger.subsystem, category: ""),
      name: nil,
      level: debugLogging ? .debug : .info)
    // If the system logger will log to stderr in the current environment, don't add a second stderr logger.
    if !writeToStdErr || systemLoggerWillLogToStdErr {
      return systemLogger
    }
    return FBCompositeLogger(loggers: [
      systemLogger,
      FBFileDescriptorLogger(fileDescriptor: STDERR_FILENO, name: nil, dateFormatter: nil),
    ])
  }

  /// Whether os_log mirrors to stderr in this environment (rdar://36919139).
  static var systemLoggerWillLogToStdErr: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["OS_ACTIVITY_DT_MODE"] != nil || environment["ACTIVITY_LOG_STDERR"] != nil || environment["CFLOG_FORCE_STDERR"] != nil
  }

  /// Strips surrounding whitespace and newlines; nil if nothing is left to log.
  static func loggableStringLine(_ string: String?) -> String? {
    guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}
