/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Loads a symbol from a dlopen handle; the process stops if the symbol cannot be found
/// (taptaptap 3e: Swift port of FBGetSymbolFromHandle, which NSCAssert-ed the same condition).
public func FBGetSymbolFromHandle(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer {
  guard let symbol = dlsym(handle, name) else {
    fatalError("\(name) could not be located")
  }
  return symbol
}

/// A base framework loader: loads a named set of weak (private) frameworks once
/// (taptaptap 3e: Swift port of FBControlCoreFrameworkLoader.m).
open class FBControlCoreFrameworkLoader {

  /// The name of the loading framework.
  public let frameworkName: String

  /// The frameworks to load.
  public let frameworks: [FBWeakFramework]

  private let lock = NSLock()
  private var loaded = false

  public init(name frameworkName: String, frameworks: [FBWeakFramework]) {
    self.frameworkName = frameworkName
    self.frameworks = frameworks
  }

  /// true once the frameworks have loaded successfully.
  public var hasLoadedFrameworks: Bool {
    lock.lock()
    defer { lock.unlock() }
    return loaded
  }

  /// Loads the frameworks (a no-op after the first success).
  public func loadPrivateFrameworks(_ logger: (any FBControlCoreLogger)?) throws {
    lock.lock()
    defer { lock.unlock() }
    if loaded {
      return
    }
    for framework in frameworks {
      try framework.load(with: logger)
    }
    logger?.debug().log("Loaded All Private Frameworks \(FBCollectionInformation.oneLineDescription(from: frameworks.map(\.name), atKeyPath: "lastPathComponent"))")
    loaded = true
  }

  /// Loads the frameworks, stopping the process if they cannot be loaded.
  public func loadPrivateFrameworksOrAbort() {
    let logger = FBControlCoreGlobalConfiguration.defaultLogger.withName("framework_loader")
    do {
      try loadPrivateFrameworks(logger.debug())
    } catch {
      let message = "Failed to private frameworks for \(frameworkName) with error \(error)"
      logger.error().log(message)
      fatalError(message)
    }
  }
}

extension Bundle {
  /// dlopen()s this loaded bundle's executable. nil if the bundle is not loaded or dlopen fails (the
  /// ObjC original asserted both).
  public func dlopenExecutablePath() -> UnsafeMutableRawPointer? {
    guard isLoaded, let path = executablePath else {
      return nil
    }
    return dlopen(path, RTLD_LAZY)
  }
}
