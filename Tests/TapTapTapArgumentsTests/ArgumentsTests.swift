import Testing
@testable import TapTapTapArguments

private struct Sample: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sample", abstract: "A sample.")

    @Option(name: .customShort("x"), help: "X.")
    var x: Double?

    @Option(name: .customLong("udid"), help: "The UDID.")
    var udid: String

    @Option(name: .customLong("step"), help: "Step.")
    var steps: [String] = []

    @Flag(name: .customLong("verbose"), help: "Verbose.")
    var verbose: Bool = false

    @Argument(help: "Text.")
    var text: String?

    func run() async throws {}
}

@Suite("Hand-written argument parser")
struct ArgumentsTests {
    private func parse(_ tokens: [String]) throws -> ParseOutcome<Sample> {
        try CommandArgumentsParser.parse(Sample.self, tokens, versionAvailable: true)
    }

    private func command(_ tokens: [String]) throws -> Sample {
        guard case .command(let command) = try parse(tokens) else {
            Issue.record("expected a command for \(tokens)")
            return Sample()
        }
        return command
    }

    @Test("Values: separate, attached with =, repeated, last scalar wins")
    func values() throws {
        let parsed = try command(["-x=5", "--udid=A", "--udid", "B", "--step", "a", "--step=b", "--verbose", "hello"])
        #expect(parsed.x == 5)
        #expect(parsed.udid == "B")
        #expect(parsed.steps == ["a", "b"])
        #expect(parsed.verbose)
        #expect(parsed.text == "hello")
    }

    @Test("A value that looks like an option is never taken: -x5, -x -5, --udid= are missing values")
    func missingValues() {
        for tokens in [["-x5", "--udid", "A"], ["-x", "-5", "--udid", "A"], ["--udid="]] {
            #expect(throws: ParseError.self) { try parse(tokens) }
        }
    }

    @Test("Help beats a missing required argument and unknown options, not a missing value")
    func helpPrecedence() throws {
        guard case .help = try parse(["--bogus", "-h"]) else {
            Issue.record("expected help"); return
        }
        #expect(throws: ParseError.self) { try parse(["--help", "--udid"]) }
    }

    @Test("After --, everything is positional")
    func terminator() throws {
        let parsed = try command(["--udid", "A", "--", "--verbose"])
        #expect(parsed.text == "--verbose")
        #expect(!parsed.verbose)
    }

    @Test("Names and wrapping")
    func namesAndWrapping() {
        #expect("DescribeUI".kebabCased() == "describe-ui")
        #expect("buttonType".kebabCased() == "button-type")
        #expect("URLSession".kebabCased() == "url-session")
        #expect("--label".editDistance(to: "--lable") == 2)
        #expect("aaa bbb ccc".wrapped(to: 8) == "aaa bbb\nccc")
        #expect("aaa bbb".wrapped(to: 8, indent: 2) == "  aaa\n  bbb")
    }
}

// MARK: - N-level subcommand dispatch (Phase 4: `taptaptap ui tap 100 200` needs root -> ui -> tap)

/// Records which leaf actually ran, since `CommandRunner.run` prints to real stdout/stderr and
/// returns only an exit code — this is the cheapest way to prove dispatch reached the right leaf.
private final class DispatchSpy: @unchecked Sendable {
    static var lastLeaf: String?
}

private struct NestedLeaf: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tap", abstract: "Leaf command.")
    @Argument(help: "X.") var x: Int?
    @Argument(help: "Y.") var y: Int?
    func run() async throws { DispatchSpy.lastLeaf = "tap \(x.map(String.init) ?? "-"),\(y.map(String.init) ?? "-")" }
}

private struct NestedOtherLeaf: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Another leaf.")
    func run() async throws { DispatchSpy.lastLeaf = "swipe" }
}

private struct NestedGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui", abstract: "UI group.",
        subcommands: [NestedLeaf.self, NestedOtherLeaf.self]
    )
}

private struct NestedRoot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "root", abstract: "Root.", version: "9.9.9",
        subcommands: [NestedGroup.self]
    )
}

@Suite("N-level subcommand dispatch", .serialized)
struct NestedDispatchTests {
    @Test("root -> group -> leaf: two hops, positionals reach the leaf")
    func twoLevelDispatch() async {
        DispatchSpy.lastLeaf = nil
        let code = await CommandRunner.run(NestedRoot.self, arguments: ["ui", "tap", "100", "200"])
        #expect(code == 0)
        #expect(DispatchSpy.lastLeaf == "tap 100,200")
    }

    @Test("A second leaf under the same group dispatches independently")
    func secondLeafInSameGroup() async {
        DispatchSpy.lastLeaf = nil
        let code = await CommandRunner.run(NestedRoot.self, arguments: ["ui", "swipe"])
        #expect(code == 0)
        #expect(DispatchSpy.lastLeaf == "swipe")
    }

    @Test("An option-looking token stops descent: 'ui --help' parses against the group, not a leaf")
    func optionTokenStopsDescent() async {
        DispatchSpy.lastLeaf = nil
        let code = await CommandRunner.run(NestedRoot.self, arguments: ["ui", "--help"])
        #expect(code == 0)
        #expect(DispatchSpy.lastLeaf == nil)
    }

    @Test("An unmatched name at the leaf level is a usage error (exit 64), not a silent no-op")
    func unmatchedNameIsUsageError() async {
        let code = await CommandRunner.run(NestedRoot.self, arguments: ["ui", "bogus"])
        #expect(code == 64)
    }

    @Test("'help ui tap' (root-level help shortcut) resolves two levels deep")
    func helpShortcutTwoLevelsDeep() async {
        let code = await CommandRunner.run(NestedRoot.self, arguments: ["help", "ui", "tap"])
        #expect(code == 0)
    }
}
