import Testing
import Foundation
@testable import TapTapTapCLI
@testable import TapTapTapArguments

/// Every command example documented in skills/taptaptap/SKILL.md (the idb parity table, the full
/// command reference, and the recipes) must at least *parse* successfully against the real
/// command tree — argument shape, positional/option binding, enum values and `validate()` all run;
/// only `run()` (the part that talks to the simulator) is skipped, so this needs no booted
/// simulator and no network. Keep this list in sync with SKILL.md by hand when either changes.
@Suite("Documented command examples parse")
struct DocExampleParsingTests {
    /// Walks the real root command's subcommand tree the same way CommandRunner does, then parses
    /// the remaining tokens against the deepest match -- stopping short of run().
    private func parses(_ argv: String) throws -> Bool {
        let tokens = try GoldenCaseTests.shellWords("taptaptap " + argv)
        var stack: [any ParsableCommand.Type] = [TapTapTap.self]
        var remaining = Array(tokens.dropFirst())
        while let first = remaining.first, !first.hasPrefix("-"),
              let match = stack.last!.configuration.subcommands.first(where: { $0.commandName == first }) {
            stack.append(match)
            remaining = Array(remaining.dropFirst())
        }
        guard let leaf = stack.last as? any AsyncParsableCommand.Type else {
            return false
        }
        return try parseLeaf(leaf, remaining)
    }

    private func parseLeaf<C: AsyncParsableCommand>(_ type: C.Type, _ tokens: [String]) throws -> Bool {
        switch try CommandArgumentsParser.parse(type, tokens, versionAvailable: true) {
        case .command, .help, .version:
            return true
        }
    }

    // MARK: - idb parity table (skills/taptaptap/SKILL.md "idb parity table")

    static let parityTableExamples = [
        "list-targets",
        "ui describe-all",
        "ui describe-point 200 400",
        "ui tap 201 319",
        "ui swipe 200 700 200 250 --duration 0.3",
        "ui text \"hello\"",
        "ui key 40",
        "ui button HOME",
        "screenshot out.png",
        "record-video out.mp4",
        "video out.mp4",
    ]

    @Test("idb parity table row", arguments: parityTableExamples)
    func parityTableRowParses(_ example: String) throws {
        #expect(try parses(example), "expected '\(example)' to parse")
    }

    // MARK: - Full command reference (skills/taptaptap/SKILL.md "Full command reference")

    static let referenceExamples = [
        "ui tap 120 400",
        "ui tap --label \"Sign In\"",
        "ui tap --id LoginButton --element-type Button --wait-timeout 5",
        "ui tap --label \"Wi-Fi\" --element-type Switch",
        "ui multi-tap 120 400 --count 2 --pause 0.1",
        "ui touch 200 400 --down --up --delay 1.0",
        "ui swipe 200 700 200 250 --duration 0.3",
        "ui drag 50 500 300 500 --duration 0.6 --steps 60",
        "ui gesture scroll-down",
        "ui gesture scroll-up",
        "ui gesture scroll-left",
        "ui gesture scroll-right",
        "ui gesture swipe-from-left-edge",
        "ui gesture swipe-from-bottom-edge",
        "ui gesture swipe-from-top-edge",
        "ui gesture swipe-from-right-edge",
        "ui text 'hello world'",
        "ui text --stdin",
        "ui text --file f.txt",
        "ui key 40",
        "ui key 42 --duration 1",
        "ui key 4 --command",
        "ui key-sequence 11 8 15 15 18 --delay 0.1",
        "ui key-combo --modifiers 227 --key 4",
        "ui button HOME",
        "ui button LOCK",
        "ui button SIDE_BUTTON",
        "ui button SIRI",
        "ui button APPLE_PAY",
        "ui slider --id VolumeSlider --value 75",
        "ui describe-all --nested",
        "ui describe-point 200 400",
        "ui pinch 200 400 2.0",
        "list-targets --json",
        "describe --json",
        "screenshot shot.png",
        "screenshot -",
        "record-video run.mp4 --duration 5 --fps 10 --quality 80 --scale 0.5",
        "video run.mp4",
        "record video run.mp4",
        "batch --step \"tap --id General\" --step \"sleep 0.5\" --step \"gesture scroll-down\"",
    ]

    @Test("Full command reference example", arguments: referenceExamples)
    func referenceExampleParses(_ example: String) throws {
        #expect(try parses(example), "expected '\(example)' to parse")
    }

    // MARK: - Recipes (skills/taptaptap/SKILL.md "Recipes")

    static let recipeExamples = [
        "ui tap --label \"General\" --wait-timeout 5",
        "ui describe-all",
        "batch --step \"tap --label Email\" --step \"text 'me@example.com'\" --step \"tap --label Password\" --step \"text 'hunter2'\" --step \"key 40\"",
        "ui tap --id BackButton",
        "record-video repro.mp4 --duration 5",
        "record-video repro.mp4 --duration 8",
    ]

    @Test("Recipe example", arguments: recipeExamples)
    func recipeExampleParses(_ example: String) throws {
        #expect(try parses(example), "expected '\(example)' to parse")
    }

    // MARK: - Unsupported-command pointer example (skills/taptaptap/SKILL.md "Unsupported idb commands")

    @Test("Unsupported command example parses (it fails at run(), not at parse)")
    func unsupportedCommandExampleParses() throws {
        #expect(try parses("install MyApp.app"))
    }

    // MARK: - Setup check (skills/taptaptap/SKILL.md "Setup check")

    @Test("--version parses")
    func versionParses() throws {
        #expect(try parses("--version"))
    }
}
