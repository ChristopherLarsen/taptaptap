import Testing
import Foundation
@testable import TapTapTapCLI

/// Pure validation tests for `--duration` (F1, TESTING.md): taptaptap-only, not gated by
/// isE2EEnabled since `VideoRecordCore.validate` needs no simulator. Live self-termination and
/// signal-finalization behavior is covered by `scripts/e2e-settings.sh` (checks 6a-6c), which
/// needs a real booted simulator and an AVAssetWriter output to inspect.
@Suite("Video Record Core Tests")
struct VideoRecordCoreTests {
    private func options(duration: Double?) -> VideoRecordCore.Options {
        VideoRecordCore.Options(udid: nil, fps: 10, quality: 80, scale: 1.0, outputFile: "out.mp4", duration: duration)
    }

    @Test("No --duration is valid (signal-only mode, unchanged default)")
    func noDurationIsValid() throws {
        try VideoRecordCore.validate(options(duration: nil))
    }

    @Test("A positive --duration within bounds is valid")
    func positiveDurationIsValid() throws {
        try VideoRecordCore.validate(options(duration: 3))
        try VideoRecordCore.validate(options(duration: 0.5))
        try VideoRecordCore.validate(options(duration: 3600))
    }

    @Test("Zero or negative --duration is rejected")
    func nonPositiveDurationIsRejected() {
        #expect(throws: (any Error).self) {
            try VideoRecordCore.validate(options(duration: 0))
        }
        #expect(throws: (any Error).self) {
            try VideoRecordCore.validate(options(duration: -1))
        }
    }

    @Test("--duration over 3600 seconds is rejected")
    func excessiveDurationIsRejected() {
        #expect(throws: (any Error).self) {
            try VideoRecordCore.validate(options(duration: 3601))
        }
    }
}
