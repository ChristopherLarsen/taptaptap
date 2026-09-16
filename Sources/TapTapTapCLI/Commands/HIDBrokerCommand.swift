import TapTapTapArguments
import Darwin
import Foundation
import TapTapTapCore

struct HIDBrokerCommand: AsyncParsableCommand {
    // This hidden command is the process entry point used by AXe's HID client. It is an internal
    // implementation detail rather than a supported public CLI command.
    static let configuration = CommandConfiguration(
        commandName: "hid-broker",
        shouldDisplay: false
    )

    @Option(name: .customLong("udid"))
    var simulatorUDID: String

    func run() async throws {
        let endpoint = try HIDBroker.endpointPath(simulatorUDID: simulatorUDID)
        // F3 (TESTING.md): prune stale endpoint files left by broker processes that exited
        // without cleanup, once per broker startup rather than on every command. Excludes this
        // broker's own about-to-be-(re)created identity to avoid a harmless-but-wasteful race
        // with a concurrent client's liveness check (HIDBroker+Connection.swift).
        HIDBroker.pruneStaleEndpoints(
            rootDirectory: (endpoint as NSString).deletingLastPathComponent,
            excludingIdentity: (endpoint as NSString).lastPathComponent
        )
        let lifetimeLock = try HIDBroker.acquireLifetimeLock(endpoint: endpoint)
        defer {
            _ = flock(lifetimeLock, LOCK_UN)
            Darwin.close(lifetimeLock)
        }
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        try await HIDBroker.serve(simulatorUDID: simulatorUDID, logger: logger)
    }
}
