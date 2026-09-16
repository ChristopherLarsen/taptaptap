import TapTapTapArguments
import Foundation

/// idb: `ui describe-point <x> <y> [--nested]` (accessibility.py:38-62). Changed from taptaptap's
/// old `--point "x,y"` string option to idb's two positionals.
struct DescribePoint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "describe-point",
        abstract: "Describes Accessibility Information at a point on the screen"
    )

    @Argument(help: "The X coordinate.")
    var x: Double

    @Argument(help: "The Y coordinate.")
    var y: Double

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    @Flag(name: .customLong("nested"), help: "Will report data in the newer nested format, rather than the flat one.")
    var nested: Bool = false

    func validate() throws {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0 else {
            throw ValidationError("<x> <y> must be non-negative numbers.")
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let jsonData = try await AccessibilityFetcher.fetchAccessibilityInfoJSONData(
            for: simulatorUDID,
            point: AccessibilityPoint(x: x, y: y),
            nested: nested,
            logger: logger
        )
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CLIError(errorDescription: "Failed to convert accessibility info to JSON string.")
        }
        print(jsonString)
    }
}
