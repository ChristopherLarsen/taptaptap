import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb's --udid resolution (IDB-COMPAT.md §3): explicit --udid > $IDB_UDID env > the sole booted
/// simulator > a clear error listing every booted UDID. Split into pure, synchronously-testable
/// logic (`resolveWithoutBooting`, `resolveFromBooted`) and the async wrapper that actually asks
/// CoreSimulator which UDIDs are booted, so the 0/1/2+-booted decision can be unit-tested against
/// an injected list without booting real simulators for every case.
enum TargetResolver {
    /// `nil` means "still need the booted-simulator list" (only reached when neither --udid nor
    /// $IDB_UDID was given).
    static func resolveWithoutBooting(explicit: String?, environmentUDID: String?) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        if let environmentUDID, !environmentUDID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentUDID
        }
        return nil
    }

    static func resolveFromBooted(_ bootedUDIDs: [String]) throws -> String {
        switch bootedUDIDs.count {
        case 1:
            return bootedUDIDs[0]
        case 0:
            throw CLIError(errorDescription: "No simulator is booted. Boot one first (`xcrun simctl boot <udid>`) or pass --udid.")
        default:
            let list = bootedUDIDs.sorted().joined(separator: ", ")
            throw CLIError(errorDescription: "Multiple simulators are booted (\(list)); pass --udid to choose one.")
        }
    }
}

/// Live wrapper: resolves `explicit` (a command's own `--udid` value) to a concrete UDID,
/// consulting `$IDB_UDID` and, only if neither is set, the set of currently-booted simulators.
@MainActor
func resolveSimulatorUDID(_ explicit: String?, logger: AxeLogger) async throws -> String {
    if let resolved = TargetResolver.resolveWithoutBooting(
        explicit: explicit,
        environmentUDID: ProcessInfo.processInfo.environment["IDB_UDID"]
    ) {
        return resolved
    }
    let simulatorSet = try await getSimulatorSet(deviceSetPath: nil, logger: logger, reporter: EmptyEventReporter.shared)
    let bootedUDIDs = simulatorSet.allSimulators.filter { $0.state == .booted }.map(\.udid)
    return try TargetResolver.resolveFromBooted(bootedUDIDs)
}
