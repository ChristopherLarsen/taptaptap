/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Queries for processes running on the host (taptaptap 3e: Swift port of FBProcessFetcher.m).
/// Not thread-safe: an instance reuses its buffers between calls.
public final class FBProcessFetcher {

  // KERN_ARGMAX, read once (the ObjC original read it in +load).
  private static let maxArgumentBufferSize: Int = {
    var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctl(&mib, 2, &value, &size, nil, 0) != -1, value > 0 else {
      return Int(ARG_MAX)
    }
    return Int(value)
  }()

  // From 'ulimit -u', but twice as large.
  private static let maxProcessIdentifiers = 5568 * 2

  private var argumentBuffer = [UInt8](repeating: 0, count: FBProcessFetcher.maxArgumentBufferSize)
  private var pidBuffer = [pid_t](repeating: 0, count: FBProcessFetcher.maxProcessIdentifiers)

  public init() {}

  // MARK: Queries

  /// All of the process information for a process identifier, or nil if it cannot be read.
  func processInfo(for processIdentifier: pid_t) -> FBProcessInfo? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
    var size = argumentBuffer.count
    let status = argumentBuffer.withUnsafeMutableBytes { buffer in
      sysctl(&mib, 3, buffer.baseAddress, &size, nil, 0)
    }
    guard status != -1, size > 0, size <= argumentBuffer.count else {
      return nil
    }
    guard let parsed = Self.parseProcessArguments(argumentBuffer[0..<size]) else {
      return nil
    }
    return FBProcessInfo(
      processIdentifier: processIdentifier,
      launchPath: parsed.launchPath,
      arguments: parsed.arguments,
      environment: parsed.environment)
  }

  /// The processes whose name is exactly `processName`.
  public func processes(withProcessName processName: String) -> [FBProcessInfo] {
    var processes: [FBProcessInfo] = []
    for processIdentifier in listProcessIdentifiers({ proc_listallpids($0, $1) }) {
      guard let name = Self.processName(of: processIdentifier, minimumLength: 2), name == processName else {
        continue
      }
      guard let info = processInfo(for: processIdentifier) else {
        continue
      }
      processes.append(info)
    }
    return processes
  }

  /// The first child of `parent` whose name contains `name`, or -1 if there is none.
  public func subprocess(of parent: pid_t, withName name: String) -> pid_t {
    for processIdentifier in listProcessIdentifiers({ proc_listchildpids(parent, $0, $1) }) {
      guard let processName = Self.processName(of: processIdentifier, minimumLength: 1), processName.contains(name) else {
        continue
      }
      return processIdentifier
    }
    return -1
  }

  // MARK: Private

  private func listProcessIdentifiers(_ caller: (UnsafeMutableRawPointer?, Int32) -> Int32) -> [pid_t] {
    let capacity = pidBuffer.count
    let count = pidBuffer.withUnsafeMutableBytes { buffer in
      caller(buffer.baseAddress, Int32(buffer.count))
    }
    guard count > 0 else {
      return []
    }
    return Array(pidBuffer[0..<min(Int(count), capacity)])
  }

  // proc_name returns the name length, or 0 on failure. A fresh buffer per call means a failed lookup
  // can never match on a previous process's name.
  private static func processName(of processIdentifier: pid_t, minimumLength: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let length = buffer.withUnsafeMutableBytes { proc_name(processIdentifier, $0.baseAddress, UInt32($0.count)) }
    guard length >= minimumLength else {
      return nil
    }
    return String(cString: buffer)
  }

  /// Parses a KERN_PROCARGS2 buffer: an Int32 argc, the NUL-terminated executable path, NUL padding,
  /// argc NUL-terminated arguments, then NUL-terminated KEY=VALUE environment strings up to an empty
  /// string. (Layout from libtop.c in Apple's top(1).) Every read is bounds-checked against the
  /// buffer; a truncated or malformed buffer yields nil rather than reading past the end.
  static func parseProcessArguments(_ bytes: ArraySlice<UInt8>) -> (launchPath: String, arguments: [String], environment: [String: String])? {
    let intSize = MemoryLayout<Int32>.size
    guard bytes.count >= intSize else {
      return nil
    }
    let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard argc >= 1 else {
      return nil
    }
    var position = bytes.startIndex + intSize

    func readCString() -> String? {
      guard position < bytes.endIndex, let terminator = bytes[position...].firstIndex(of: 0) else {
        return nil
      }
      let string = String(decoding: bytes[position..<terminator], as: UTF8.self)
      position = terminator + 1
      return string
    }

    guard let launchPath = readCString() else {
      return nil
    }
    while position < bytes.endIndex, bytes[position] == 0 {
      position += 1
    }
    var arguments: [String] = []
    for _ in 0..<argc {
      guard let argument = readCString() else {
        return nil
      }
      arguments.append(argument)
    }
    var environment: [String: String] = [:]
    while position < bytes.endIndex, bytes[position] != 0 {
      guard let entry = readCString() else {
        break
      }
      let tokens = entry.components(separatedBy: "=")
      // If we don't get 2 tokens, something is malformed.
      guard tokens.count == 2 else {
        break
      }
      environment[tokens[0]] = tokens[1]
    }
    return (launchPath, arguments, environment)
  }
}
