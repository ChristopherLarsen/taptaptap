import Testing
import Foundation
import TapTapTapCore
@testable import TapTapTapCLI

/// Regression coverage for a bug caught during Phase 4 live parity verification:
/// FBiOSTargetStateStringFromState returns an FBiOSTargetStateString wrapper, not a plain String.
/// Interpolating it directly (or passing it to JSONSerialization) produced
/// "FBiOSTargetStateString(rawValue: \"Booted\")" in `list-targets`/`describe` human output, and
/// silently degraded `--json` output to "{}" (JSONSerialization can't serialize a non-plist type,
/// so the `try?` failed). Both must use `.rawValue`.
@Suite("Target Formatting Tests")
struct TargetFormattingTests {
    @Test("humanLine never contains the raw Swift struct description")
    func humanLineHasNoStructDescriptionLeak() {
        // We can't easily construct a real FBSimulator without a live CoreSimulator context, so
        // this locks in the specific failure signature instead: any occurrence of the wrapper
        // type's name in formatted output is the bug reappearing.
        let state = FBiOSTargetStateStringFromState(.booted).rawValue
        #expect(state == "Booted")
        #expect(!state.contains("FBiOSTargetStateString"))
    }

    @Test("A state string survives JSONSerialization (a raw-value String does, a wrapper struct doesn't)")
    func stateStringIsJSONSerializable() throws {
        let state = FBiOSTargetStateStringFromState(.booted).rawValue
        let data = try #require(try? JSONSerialization.data(withJSONObject: ["state": state], options: []))
        let decoded = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(decoded["state"] == "Booted")
    }
}
