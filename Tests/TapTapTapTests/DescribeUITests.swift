import Testing
import Foundation

@Suite("Describe UI Command Surface Tests")
struct DescribeUICommandSurfaceTests {
    @Test("describe-point takes two positional coordinates")
    func describePointHelpIncludesCoordinates() async throws {
        let result = try await TestHelpers.runAxeCommand("ui describe-point --help")
        #expect(result.output.contains("<x>"))
        #expect(result.output.contains("<y>"))
    }

    @Test("--point appears in help ui describe-point")
    func helpDescribePointIncludesCoordinates() async throws {
        let result = try await TestHelpers.runAxeCommand("help ui describe-point")
        #expect(result.output.contains("<x>"))
        #expect(result.output.contains("<y>"))
    }

    @Test("Non-numeric describe-point coordinates fail with a usage error")
    func invalidPointFormatFails() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure("ui describe-point nope 5 --udid invalid")
        #expect(result.exitCode != 0)
    }

    @Test("Negative describe-point coordinates fail validation")
    func negativePointFailsValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure("ui describe-point -1 5 --udid invalid")
        #expect(result.exitCode != 0)
    }
}
