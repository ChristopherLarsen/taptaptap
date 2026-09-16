import Foundation
import Testing

/// Replays the recorded command-surface goldens (Tests/Goldens) against the built binary: exact
/// stdout, stderr and exit code. Cases that need a booted simulator (an @UDID@ argument) and the
/// version case (the version string is not frozen) are left to scripts/check-goldens.py.
@Suite("Golden Command Surface Cases")
struct GoldenCaseTests {
    static let goldensRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Goldens")

    // Phase 4 (docs/IDB-COMPAT.md §8): "parser/cases" (71 cases) was recorded from AXe's real
    // swift-argument-parser build using AXe's own AXe-style command surface (`tap -x5 -y5 ...`,
    // `describe-ui`, `list-simulators`, ...) purely as a fixture vehicle -- it is the proof that
    // TapTapTapArguments parses identically to swift-argument-parser (AUDIT.md §3e/§3f). Phase 4
    // removes the AXe-style commands those cases invoke, so they can no longer run against the
    // idb-style binary. The files stay on disk, untouched, unexecuted -- git history and
    // AUDIT.md §3e/§3f already preserve their evidentiary value permanently. Only the current
    // command-surface snapshot ("stable/cases", re-recorded for the idb-style surface) runs here.
    static let caseDirectories: [URL] = {
        let sets = ["xcode-26.5-17F42_ios-26.5-23F77/stable/cases"]
        return sets.flatMap { set -> [URL] in
            let directory = goldensRoot.appendingPathComponent(set)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.sorted().map { directory.appendingPathComponent($0) }
        }.filter { directory in
            guard directory.lastPathComponent != "version",
                  let argv = try? String(contentsOf: directory.appendingPathComponent("argv.txt"), encoding: .utf8)
            else { return false }
            return !argv.contains("@UDID@")
        }
    }()

    @Test("Golden case set is present")
    func caseSetIsPresent() {
        #expect(Self.caseDirectories.count >= 40)
    }

    @Test("Golden case matches", arguments: GoldenCaseTests.caseDirectories)
    func goldenCaseMatches(_ directory: URL) throws {
        let argv = try Self.shellWords(String(contentsOf: directory.appendingPathComponent("argv.txt"), encoding: .utf8))
        let expectedStdout = try String(contentsOf: directory.appendingPathComponent("stdout.txt"), encoding: .utf8)
        let expectedStderr = try String(contentsOf: directory.appendingPathComponent("stderr.txt"), encoding: .utf8)
        let expectedExit = Int32(try String(contentsOf: directory.appendingPathComponent("exit-code.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        let stdinURL = directory.appendingPathComponent("stdin.txt")
        let stdin = FileManager.default.fileExists(atPath: stdinURL.path) ? try Data(contentsOf: stdinURL) : Data()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try TestHelpers.getAxePath())
        process.arguments = Array(argv.dropFirst())
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == expectedExit, "\(directory.lastPathComponent): exit code")
        #expect(Self.reflow(String(decoding: stdout, as: UTF8.self)) == Self.reflow(Self.substitutingToolName(expectedStdout)), "\(directory.lastPathComponent): stdout")
        #expect(Self.reflow(String(decoding: stderr, as: UTF8.self)) == Self.reflow(Self.substitutingToolName(expectedStderr)), "\(directory.lastPathComponent): stderr")
    }

    /// Mirrors scripts/check-goldens.py's `--name taptaptap` substitution: goldens were recorded
    /// against the swift-argument-parser build (behavior contract for the 3e parser swap) and are
    /// never re-recorded for the 3f rename. Replaces only the standalone word "axe" (never "AXe",
    /// "axe-hid-…" or a path component) with the current tool name.
    static func substitutingToolName(_ recorded: String) -> String {
        let pattern = #"(?<![\w/.-])axe(?![\w-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return recorded }
        let range = NSRange(recorded.startIndex..., in: recorded)
        return regex.stringByReplacingMatches(in: recorded, range: range, withTemplate: "taptaptap")
    }

    /// A longer tool name shifts where the renderer's 80-column word-wrap breaks a line — a
    /// text-layout detail, not part of the parser behavior contract these goldens exist to prove.
    /// Collapses whitespace (including single newlines) within each blank-line-delimited paragraph
    /// to single spaces, on both the recorded and actual text, so the comparison is insensitive to
    /// where a wrap lands while staying exact on content, word order and section structure.
    static func reflow(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .joined(separator: "\n\n")
    }

    /// POSIX-shell word splitting for the recorded argv lines (quotes and backslash escapes only).
    static func shellWords(_ line: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                current.append(character); escaped = false; inWord = true; continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                else if character == "\\" && activeQuote == "\"" { escaped = true }
                else { current.append(character) }
                continue
            }
            switch character {
            case "\\": escaped = true; inWord = true
            case "'", "\"": quote = character; inWord = true
            case " ", "\t", "\n":
                if inWord { words.append(current); current = ""; inWord = false }
            default: current.append(character); inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
