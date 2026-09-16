import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `describe [--diagnostics] [--json]` (target.py:139-163). `--diagnostics` is accepted and
/// ignored: taptaptap has no extra diagnostics channel beyond what `describe` already reports
/// (docs/IDB-COMPAT.md §2).
struct Describe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Describes the Target"
    )

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    @Flag(name: .customLong("diagnostics"), help: "Fetch additional target diagnostics (accepted; no extra diagnostics beyond this output).")
    var diagnostics: Bool = false

    @Flag(name: .customLong("json"), help: "Create json structured output.")
    var json: Bool = false

    func run() async throws {
        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let simulatorSet = try await getSimulatorSet(deviceSetPath: nil, logger: logger, reporter: EmptyEventReporter.shared)
        guard let target = simulatorSet.allSimulators.first(where: { $0.udid == simulatorUDID }) else {
            throw CLIError.simulatorNotFound(udid: simulatorUDID)
        }

        print(json ? TargetFormatting.jsonLine(target) : TargetFormatting.humanLine(target))
    }
}
