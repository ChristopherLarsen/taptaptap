/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct FBXcodeDirectory {

  // MARK: Public

  public static func resolveDeveloperDirectory() throws -> String {
    try resolveDeveloperDirectory(environment: ProcessInfo.processInfo.environment)
  }

  static func resolveDeveloperDirectory(environment: [String: String]) throws -> String {
    if let directory = environment["DEVELOPER_DIR"],
      !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let resolved = (directory as NSString).resolvingSymlinksInPath
      try validateXcodeDirectory(resolved)
      return resolved
    }

    let directory: String
    do {
      directory = try symlinkedDeveloperDirectory()
    } catch {
      directory = try xcodeSelectDeveloperDirectory()
    }
    return directory
  }

  public static func xcodeSelectDeveloperDirectory() throws -> String {
    // taptaptap 3c: replaces the FBProcessBuilder/FBSubprocess stack for this single call.
    // Same contract: run `/usr/bin/xcode-select --print-path`, exit code 0 required, 10 s timeout.
    let (status, stdOut, stdErr) = try runXcodeSelect(timeout: 10)
    guard status == 0 else {
      throw
        FBControlCoreError
        .describe("`xcode-select --print-path` exited with code \(status): \(stdErr)")
        .build()
    }
    let directory = stdOut
    if directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw
        FBControlCoreError
        .describe("Empty output for xcode directory returned from `xcode-select -p`: \(stdErr)")
        .build()
    }
    let resolved = (directory as NSString).resolvingSymlinksInPath
    try validateXcodeDirectory(resolved)
    return resolved
  }

  public static func symlinkedDeveloperDirectory() throws -> String {
    let directory: String = ("/var/db/xcode_select_link" as NSString).resolvingSymlinksInPath
    try validateXcodeDirectory(directory)
    return directory
  }

  // MARK: Private

  private static func runXcodeSelect(timeout: TimeInterval) throws -> (Int32, String, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["--print-path"]
    // Same allowlist as FBProcessBuilder.defaultEnvironmentForSubprocess.
    let parentEnvironment = ProcessInfo.processInfo.environment
    process.environment = ["DEVELOPER_DIR", "HOME", "PATH"].reduce(into: [String: String]()) { env, key in
      env[key] = parentEnvironment[key]
    }
    process.standardInput = FileHandle.nullDevice
    let stdOutPipe = Pipe()
    let stdErrPipe = Pipe()
    process.standardOutput = stdOutPipe
    process.standardError = stdErrPipe
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    // Drain both pipes concurrently so a full pipe buffer cannot block the child.
    var stdOutData = Data()
    var stdErrData = Data()
    let drained = DispatchGroup()
    drained.enter()
    DispatchQueue.global().async {
      stdOutData = stdOutPipe.fileHandleForReading.readDataToEndOfFile()
      drained.leave()
    }
    drained.enter()
    DispatchQueue.global().async {
      stdErrData = stdErrPipe.fileHandleForReading.readDataToEndOfFile()
      drained.leave()
    }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      throw
        FBControlCoreError
        .describe("Timed out after \(timeout) s waiting for xcode-select to return the developer directory")
        .build()
    }
    drained.wait()
    // FBProcessOutput_String stripped exactly one trailing newline.
    func contents(_ data: Data) -> String {
      String(decoding: data.last == UInt8(ascii: "\n") ? data.dropLast() : data, as: UTF8.self)
    }
    return (process.terminationStatus, contents(stdOutData), contents(stdErrData))
  }

  private static func validateXcodeDirectory(_ directory: String?) throws {
    guard let directory else {
      throw
        FBControlCoreError
        .describe("Xcode path is nil")
        .build()
    }
    guard directory != "/Library/Developer/CommandLineTools" else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '/Library/Developer/CommandLineTools', but idb requires a full Xcode install.")
        .build()
    }
    guard directory != "/" else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '/' which isn't valid.")
        .build()
    }
    guard FileManager.default.fileExists(atPath: directory) else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '\(directory)' which doesn't exist.")
        .build()
    }
    // 3f: bound DEVELOPER_DIR to something that actually looks like an Xcode Developer directory
    // (an attacker-controlled DEVELOPER_DIR is not a security boundary per the charter, but a
    // directory that merely exists and isn't CommandLineTools or "/" is too weak a check; this
    // catches the common misconfiguration case of pointing DEVELOPER_DIR at an unrelated path).
    let xcodebuildPath = (directory as NSString).appendingPathComponent("usr/bin/xcodebuild")
    guard FileManager.default.isExecutableFile(atPath: xcodebuildPath) else {
      throw
        FBControlCoreError
        .describe("'\(directory)' does not look like a full Xcode installation (missing usr/bin/xcodebuild).")
        .build()
    }
  }
}
