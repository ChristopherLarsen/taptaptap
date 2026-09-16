// swift-tools-version:5.10
// Swift 5 language mode for every target (tools-version 5.10), matching the SWIFT_VERSION = 5.0 the
// idb frameworks were built with; Swift 6 strict concurrency is out of scope for 3e.
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privateHeaders = packageRoot.appendingPathComponent("PrivateHeaders", isDirectory: true)

// Reverse-engineered Apple private-framework headers, exposed to Swift as Clang modules through the
// `module.modulemap` in each directory. Compile-time only: no header is shipped, and only the two
// .tbd stubs below reach the linker. Each search path stays one token ("-I<path>"): SwiftPM can drop a
// separate path argument when it propagates unsafe flags to the generated test runner.
let privateModuleSearchFlags = [
  privateHeaders,
  privateHeaders.appendingPathComponent("AccessibilityPlatformTranslation", isDirectory: true),
  privateHeaders.appendingPathComponent("CoreSimDeviceIO", isDirectory: true),
  privateHeaders.appendingPathComponent("CoreSimulator", isDirectory: true),
  privateHeaders.appendingPathComponent("SimulatorApp", isDirectory: true),
].map { "-I\($0.path)" }

// CoreSimulator and AccessibilityPlatformTranslation are loaded at runtime (dlopen via
// FBWeakFramework); Swift emits direct class references, so weak-link their .tbd stubs.
// SimulatorKit is loaded at runtime too, but only through dlsym and name-based class lookup, so it
// needs neither headers nor a link stub.
let privateFrameworkLinkFlags = [
  "-Xlinker", "-weak_library", "-Xlinker", privateHeaders.appendingPathComponent("CoreSimulator/CoreSimulator.tbd").path,
  "-Xlinker", "-weak_library", "-Xlinker", privateHeaders.appendingPathComponent("AccessibilityPlatformTranslation/AccessibilityPlatformTranslation.tbd").path,
]

let package = Package(
  name: "taptaptap",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "taptaptap", targets: ["TapTapTapCLI"])
  ],
  // No package dependencies: everything here is built from this repository.
  dependencies: [],
  targets: [
    // Swift cannot catch NSException; this is the only Objective-C in the package. Foundation-only,
    // no dependency on any other target.
    .target(
      name: "ObjCExceptionGuard",
      path: "Sources/ObjCExceptionGuard"
    ),
    .target(
      name: "TapTapTapCore",
      dependencies: ["ObjCExceptionGuard"],
      path: "Sources/TapTapTapCore"
    ),
    .target(
      name: "TapTapTapSimulator",
      dependencies: ["TapTapTapCore", "ObjCExceptionGuard"],
      path: "Sources/TapTapTapSimulator",
      swiftSettings: [.unsafeFlags(privateModuleSearchFlags)],
      linkerSettings: [.unsafeFlags(privateFrameworkLinkFlags)]
    ),
    // Hand-written command-line parser (replaces swift-argument-parser; Foundation only).
    .target(
      name: "TapTapTapArguments",
      path: "Sources/TapTapTapArguments"
    ),
    .target(
      name: "TapTapTapMath",
      path: "Sources/TapTapTapMath"
    ),
    .executableTarget(
      name: "TapTapTapCLI",
      dependencies: [
        "TapTapTapMath",
        "TapTapTapCore",
        "TapTapTapSimulator",
        "TapTapTapArguments",
      ],
      path: "Sources/TapTapTapCLI",
      swiftSettings: [.unsafeFlags(["-parse-as-library"] + privateModuleSearchFlags)],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-dead_strip",
          "-Xlinker", "-headerpad_max_install_names",
        ])
      ]
    ),
    .testTarget(
      name: "TapTapTapArgumentsTests",
      dependencies: ["TapTapTapArguments"],
      path: "Tests/TapTapTapArgumentsTests"
    ),
    .testTarget(
      name: "TapTapTapSimulatorTests",
      dependencies: ["TapTapTapSimulator", "TapTapTapCore"],
      path: "Tests/TapTapTapSimulatorTests",
      swiftSettings: [.unsafeFlags(privateModuleSearchFlags)]
    ),
    .testTarget(
      name: "TapTapTapTests",
      dependencies: ["TapTapTapCLI", "TapTapTapMath", "TapTapTapCore"],
      path: "Tests/TapTapTapTests",
      swiftSettings: [.unsafeFlags(privateModuleSearchFlags)]
    ),
  ]
)
