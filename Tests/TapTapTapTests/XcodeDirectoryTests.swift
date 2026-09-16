import Foundation
import Testing
@testable import TapTapTapCore

/// taptaptap 3d NOTE N5: the xcode-select runner and DEVELOPER_DIR precedence.
@Suite("Xcode developer directory resolution")
struct XcodeDirectoryTests {
    private static func xcodeSelectOutput() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--print-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    @Test("The xcode-select runner returns the resolved active developer directory")
    func xcodeSelectRunner() throws {
        let expected = (try Self.xcodeSelectOutput() as NSString).resolvingSymlinksInPath
        #expect(try FBXcodeDirectory.xcodeSelectDeveloperDirectory() == expected)
    }

    @Test("DEVELOPER_DIR takes precedence and is validated")
    func developerDirPrecedence() throws {
        let active = try FBXcodeDirectory.xcodeSelectDeveloperDirectory()
        #expect(try FBXcodeDirectory.resolveDeveloperDirectory(environment: ["DEVELOPER_DIR": active]) == active)
        #expect(try FBXcodeDirectory.resolveDeveloperDirectory(environment: ["DEVELOPER_DIR": "  "]) == FBXcodeDirectory.resolveDeveloperDirectory(environment: [:]))
        for invalid in ["/Library/Developer/CommandLineTools", "/", "/nonexistent/Xcode.app/Contents/Developer"] {
            #expect(throws: (any Error).self) { try FBXcodeDirectory.resolveDeveloperDirectory(environment: ["DEVELOPER_DIR": invalid]) }
        }
    }
}
