import TapTapTapArguments
import Foundation

/// idb: `ui describe-all [--nested] [--filter all|interactable]` (accessibility.py:15-35, the
/// only describe command idb wires `--filter` onto — `describe-point` never gets it). Output is
/// already raw JSON in both idb (`print(info.json)`) and taptaptap's AccessibilityFetcher — no
/// `--json` flag needed here, matching idb exactly.
struct DescribeAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "describe-all",
        abstract: "Describes Accessibility Information for the entire screen"
    )

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    @Flag(name: .customLong("nested"), help: "Will report data in the newer nested format, rather than the flat one.")
    var nested: Bool = false

    @Option(
        name: .customLong("filter"),
        help: "Which elements the read reports: all of them (the default), or only the interactable ones — those that carry a label, an identifier or an actionable role."
    )
    var filter: AccessibilityElementFilter = .all

    func run() async throws {
        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let jsonData = try await AccessibilityFetcher.fetchAccessibilityInfoJSONData(
            for: simulatorUDID,
            point: nil,
            nested: nested,
            filter: filter,
            logger: logger
        )
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CLIError(errorDescription: "Failed to convert accessibility info to JSON string.")
        }
        print(jsonString)
    }
}
