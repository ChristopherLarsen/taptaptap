import Testing
import Foundation
@testable import TapTapTapCLI

/// idb --udid resolution order (docs/IDB-COMPAT.md §3): explicit --udid > $IDB_UDID env > the
/// sole booted simulator > a clear error listing every booted UDID. Exercised here against an
/// injected booted-UDID list (0, 1, 2+), not real simulator boots.
@Suite("Target Resolver Tests")
struct TargetResolverTests {
    @Test("Explicit --udid wins over everything else")
    func explicitUDIDWins() {
        let resolved = TargetResolver.resolveWithoutBooting(explicit: "EXPLICIT-UDID", environmentUDID: "ENV-UDID")
        #expect(resolved == "EXPLICIT-UDID")
    }

    @Test("Blank --udid is treated as not given")
    func blankExplicitUDIDIsIgnored() {
        let resolved = TargetResolver.resolveWithoutBooting(explicit: "   ", environmentUDID: "ENV-UDID")
        #expect(resolved == "ENV-UDID")
    }

    @Test("$IDB_UDID is used when --udid is absent")
    func environmentUDIDIsUsedWhenExplicitAbsent() {
        let resolved = TargetResolver.resolveWithoutBooting(explicit: nil, environmentUDID: "ENV-UDID")
        #expect(resolved == "ENV-UDID")
    }

    @Test("Neither --udid nor $IDB_UDID: falls through to the booted-simulator list")
    func fallsThroughToBootedListWhenNeitherIsSet() {
        let resolved = TargetResolver.resolveWithoutBooting(explicit: nil, environmentUDID: nil)
        #expect(resolved == nil)
    }

    @Test("Exactly one booted simulator resolves to it")
    func oneBootedSimulatorResolves() throws {
        let resolved = try TargetResolver.resolveFromBooted(["ONLY-BOOTED"])
        #expect(resolved == "ONLY-BOOTED")
    }

    @Test("Zero booted simulators is a clear error, not a crash")
    func zeroBootedSimulatorsFails() {
        #expect(throws: (any Error).self) {
            try TargetResolver.resolveFromBooted([])
        }
    }

    @Test("Zero booted simulators error message points at simctl boot and --udid")
    func zeroBootedErrorMessage() {
        do {
            _ = try TargetResolver.resolveFromBooted([])
            Issue.record("expected an error")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("No simulator is booted"))
            #expect(message.contains("--udid"))
        }
    }

    @Test("Two or more booted simulators is a clear error listing every UDID")
    func multipleBootedSimulatorsFails() {
        do {
            _ = try TargetResolver.resolveFromBooted(["UDID-B", "UDID-A"])
            Issue.record("expected an error")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("Multiple simulators are booted"))
            #expect(message.contains("UDID-A"))
            #expect(message.contains("UDID-B"))
            #expect(message.contains("--udid"))
        }
    }
}
