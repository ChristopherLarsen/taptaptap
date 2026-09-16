/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import TapTapTapCore
@preconcurrency import Foundation

extension FBSimulator {

  public func serviceName(forProcessIdentifier pid: pid_t) async throws -> String {
    try await launchCtlCommands().serviceNameAsync(forProcessIdentifier: pid)
  }

  public func stopService(withName serviceName: String) async throws -> String {
    try await launchCtlCommands().stopServiceAsync(withName: serviceName)
  }
}

@objc(FBSimulatorLaunchCtlCommands)
public final class FBSimulatorLaunchCtlCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private let simulator: FBSimulator
  private let launchctlLaunchPath: String

  // MARK: - Initializers

  private class func launchCtlLaunchPath(for simulator: FBSimulator) throws -> String {
    let path = (simulator.device.runtime.root as NSString)
      .appendingPathComponent("bin")
      .appending("/launchctl")
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw FBSimulatorError.describe("launchctl is not an executable file at \(path)").build()
    }
    return path
  }

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLaunchCtlCommands {
    let simulator = target as! FBSimulator
    let launchctlLaunchPath = try! launchCtlLaunchPath(for: simulator)
    return FBSimulatorLaunchCtlCommands(simulator: simulator, launchctlLaunchPath: launchctlLaunchPath)
  }

  private init(simulator: FBSimulator, launchctlLaunchPath: String) {
    self.simulator = simulator
    self.launchctlLaunchPath = launchctlLaunchPath
    super.init()
  }

  // MARK: - Async

  fileprivate func serviceNameAsync(forProcessIdentifier pid: pid_t) async throws -> String {
    let pattern = "^\(NSRegularExpression.escapedPattern(for: "\(pid)"))\t"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorError.describe("Couldn't build search pattern for '\(pid)'").build()
    }
    let (serviceName, _) = try await firstServiceNameAndProcessIdentifierAsync(matching: regex)
    return serviceName
  }

  fileprivate func serviceNamesAndProcessIdentifiersAsync(matching regex: NSRegularExpression) async throws -> [String: NSNumber] {
    let text = try await runWithArgumentsAsync(["list"])
    return FBSimulatorLaunchCtlCommands.serviceNamesAndProcessIdentifiers(fromListOutput: text, matching: regex)
  }

  /// Parses `launchctl list` output ("PID<ws>Status<ws>Label" per line) into label -> pid (-1 for "-")
  /// for the lines matching `regex`; lines that are not exactly three fields or have an invalid pid
  /// are skipped. Internal for unit tests (taptaptap 3d NOTE N5).
  static func serviceNamesAndProcessIdentifiers(fromListOutput text: String, matching regex: NSRegularExpression) -> [String: NSNumber] {
    var mapping: [String: NSNumber] = [:]
    for line in text.components(separatedBy: .newlines) {
      if regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) == nil {
        continue
      }
      var processIdentifier: pid_t = 0
      guard let serviceName = try? extractServiceName(fromListLine: line, processIdentifierOut: &processIdentifier) else {
        // If extraction fails, skip the line
        continue
      }
      mapping[serviceName] = NSNumber(value: processIdentifier)
    }
    return mapping
  }

  fileprivate func firstServiceNameAndProcessIdentifierAsync(matching regex: NSRegularExpression) async throws -> (String, pid_t) {
    let serviceNameToProcessIdentifier = try await serviceNamesAndProcessIdentifiersAsync(matching: regex)
    if serviceNameToProcessIdentifier.isEmpty {
      throw FBSimulatorError.describe("No Matching processes for '\(regex.pattern)'").build()
    }
    if serviceNameToProcessIdentifier.count > 1 {
      throw FBSimulatorError.describe("Multiple Matching processes for '\(regex.pattern)' \(FBCollectionInformation.oneLineDescription(from: serviceNameToProcessIdentifier))").build()
    }
    let serviceName = serviceNameToProcessIdentifier.keys.first!
    let processIdentifier = serviceNameToProcessIdentifier.values.first!.int32Value
    return (serviceName, processIdentifier)
  }

  fileprivate func stopServiceAsync(withName serviceName: String) async throws -> String {
    do {
      return try await runWithArgumentsAsync(["stop", serviceName])
    } catch {
      throw FBSimulatorError.describe("Failed to stop service '\(serviceName)'")
        .caused(by: error as NSError)
        .build()
    }
  }

  // MARK: - Private

  class func extractServiceName(fromListLine line: String, processIdentifierOut: inout pid_t) throws -> String {
    let words = line.components(separatedBy: .whitespaces)
    guard words.count == 3 else {
      throw FBSimulatorError.describe("Output does not have exactly three words: \(FBCollectionInformation.oneLineDescription(from: words))").build()
    }
    let serviceName = words.last!
    let processIdentifierString = words.first!
    if processIdentifierString == "-" {
      processIdentifierOut = -1
      return serviceName
    }

    let processIdentifierInteger = Int(processIdentifierString) ?? 0
    guard processIdentifierInteger >= 1 else {
      throw FBSimulatorError.describe("Expected a process identifier as first word, but got \(processIdentifierString) from \(FBCollectionInformation.oneLineDescription(from: words))").build()
    }
    processIdentifierOut = pid_t(processIdentifierInteger)
    return serviceName
  }

  private func runWithArgumentsAsync(_ arguments: [String]) async throws -> String {
    // taptaptap 3c: replaces FBProcessSpawnConfiguration + FBProcessIO + FBSimulatorProcessSpawnCommands
    // for this single use. Same contract as FBProcessSpawnCommandHelpers.launchConsumingStdout with
    // FBProcessIO.outputToDevNull(): argv[0] = launch path, empty environment, stdout captured,
    // stderr to /dev/null, standalone iff the simulator is not booted, exit code ignored,
    // termination by signal is an error.
    try await FBSimulatorLaunchCtlCommands.spawnConsumingStdout(
      simulator: simulator,
      launchPath: launchctlLaunchPath,
      arguments: arguments
    )
  }

  private final class SpawnState: @unchecked Sendable {
    let lock = NSLock()
    var output = Data()
    var outputDrained = false
    var statLoc: Int32?
    var continuation: CheckedContinuation<String, Error>?
    var resumed = false
  }

  private static func spawnConsumingStdout(simulator: FBSimulator, launchPath: String, arguments: [String]) async throws -> String {
    let pipe = Pipe()
    guard let devNull = FileHandle(forWritingAtPath: "/dev/null") else {
      throw FBSimulatorError.describe("Could not open /dev/null").build()
    }
    let options: [String: Any] = [
      "arguments": [launchPath] + arguments,
      "environment": [String: String](),
      "stdout": NSNumber(value: pipe.fileHandleForWriting.fileDescriptor),
      "stderr": NSNumber(value: devNull.fileDescriptor),
      "standalone": NSNumber(value: simulator.state != .booted),
    ]
    let processName = (launchPath as NSString).lastPathComponent
    let logger = simulator.logger
    let state = SpawnState()

    func finishIfReady() {
      // Called with state.lock held.
      guard !state.resumed, state.outputDrained, let statLoc = state.statLoc, let continuation = state.continuation else {
        return
      }
      state.resumed = true
      let wstatus = statLoc & 0x7f
      if wstatus != 0x7f && wstatus != 0 {
        let message = "Process (\(processName)) exited with signal \(wstatus)"
        logger?.log(message)
        continuation.resume(throwing: FBControlCoreError.describe(message).build())
      } else {
        logger?.log("Process (\(processName)) exited with code \((statLoc >> 8) & 0xff)")
        continuation.resume(returning: String(decoding: state.output, as: UTF8.self))
      }
    }

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      state.lock.lock()
      state.continuation = continuation
      state.lock.unlock()
      // Drain stdout until every write end (ours, closed at termination, and the child's) is closed.
      DispatchQueue.global().async {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        state.lock.lock()
        state.output = data
        state.outputDrained = true
        finishIfReady()
        state.lock.unlock()
      }
      simulator.device.spawnAsync(
        withPath: launchPath,
        options: options,
        terminationQueue: simulator.workQueue,
        terminationHandler: { statLoc in
          try? pipe.fileHandleForWriting.close()
          try? devNull.close()
          state.lock.lock()
          state.statLoc = statLoc
          finishIfReady()
          state.lock.unlock()
        },
        completionQueue: simulator.workQueue,
        completionHandler: { error, _ in
          guard let error else { return }
          try? pipe.fileHandleForWriting.close()
          try? devNull.close()
          state.lock.lock()
          if !state.resumed {
            state.resumed = true
            state.continuation?.resume(throwing: error)
          }
          state.lock.unlock()
        }
      )
    }
  }
}
