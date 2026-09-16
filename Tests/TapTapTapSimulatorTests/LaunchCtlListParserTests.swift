import Foundation
import Testing
@testable import TapTapTapSimulator

/// taptaptap 3d NOTE N5: the SpringBoard remediation path parses `launchctl list` from inside the
/// simulator; the e2e gate cannot reach it (it needs a stale SpringBoard), so the parser is tested here.
@Suite("launchctl list parser")
struct LaunchCtlListParserTests {
    static let output = """
    PID\tStatus\tLabel
    412\t0\tcom.apple.CoreSimulator.bridge
    -\t0\tcom.apple.idle.service
    413\t-9\tcom.apple.SpringBoard
    notapid\t0\tcom.apple.bogus
    500\t0\ttoo many fields
    0\t0\tcom.apple.zero
    é1\t0\tcom.apple.unicode
    7\t0\tcom.apple.😀

    """

    private func parse(_ pattern: String) throws -> [String: NSNumber] {
        FBSimulatorLaunchCtlCommands.serviceNamesAndProcessIdentifiers(
            fromListOutput: Self.output, matching: try NSRegularExpression(pattern: pattern))
    }

    @Test("A pid-anchored pattern finds exactly that service")
    func pidLookup() throws {
        #expect(try parse("^412\\t") == ["com.apple.CoreSimulator.bridge": 412])
    }

    @Test("A '-' pid maps to -1; malformed lines are skipped")
    func allLines() throws {
        let mapping = try parse(".")
        #expect(mapping["com.apple.CoreSimulator.bridge"] == 412)
        #expect(mapping["com.apple.idle.service"] == -1)
        #expect(mapping["com.apple.SpringBoard"] == 413)
        #expect(mapping["com.apple.bogus"] == nil)
        #expect(mapping["com.apple.zero"] == nil)
        #expect(mapping["com.apple.unicode"] == nil)
        #expect(mapping["com.apple.😀"] == 7)
        #expect(mapping.count == 4)
    }

    @Test("The match range covers the whole line in UTF-16 (a trailing emoji still matches)")
    func utf16Range() throws {
        #expect(try parse("😀$") == ["com.apple.😀": 7])
    }
}
