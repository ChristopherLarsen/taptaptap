import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `list-targets [--only] [--json]` (target.py:170-202), a ManagementCommand — no --udid.
/// `--only` (idb's device-type filter) is not implemented: taptaptap only ever lists simulators
/// (physical devices are out of the charter's scope), so there is nothing for the filter to
/// select between (docs/IDB-COMPAT.md §2). Human row format matches idb's
/// `human_format_target_info` exactly.
struct ListTargets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-targets",
        abstract: "Lists connected and available targets"
    )

    @Flag(name: .customLong("json"), help: "Create json structured output.")
    var json: Bool = false

    func run() async throws {
        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)

        let simulatorSet = try await getSimulatorSet(
            deviceSetPath: nil,
            logger: logger,
            reporter: EmptyEventReporter.shared
        )

        let simulators = simulatorSet.allSimulators.sorted { $0.name < $1.name }
        if simulators.isEmpty {
            if !json {
                print("No available targets")
            }
            return
        }

        for simulator in simulators {
            print(json ? TargetFormatting.jsonLine(simulator) : TargetFormatting.humanLine(simulator))
        }
    }
}
