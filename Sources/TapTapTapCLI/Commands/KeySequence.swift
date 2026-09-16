import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui key-sequence [<keycode> ...]` (hid.py:153-171), space-separated positionals
/// (`nargs="*"`). Changed from taptaptap's old `--keycodes 1,2,3` comma-separated option. Zero
/// arguments parses successfully and is a no-op, matching idb's `nargs="*"` (not an error) — see
/// docs/IDB-COMPAT.md §2.
struct KeySequence: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key-sequence",
        abstract: "A sequence of short presses of a keycode",
        discussion: """
        Press multiple keys in sequence using their HID keycode values.
        Each key will be pressed and released before the next key is pressed.

        Examples:
          taptaptap ui key-sequence 11 8 15 15 18 --udid SIMULATOR_UDID   # Type "hello" (h=11, e=8, l=15, l=15, o=18)
          taptaptap ui key-sequence 40 40 40 --udid SIMULATOR_UDID        # Press Enter 3 times
        """
    )

    /// List of space separated key codes (i.e. 1 2 3).
    @Argument var keySequence: [Int] = []

    @Option(name: .customLong("delay"), help: "Delay between key presses in seconds (default: 0.1).")
    var delay: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        for keycode in keySequence {
            guard keycode >= 0 && keycode <= 255 else {
                throw ValidationError("All keycodes must be between 0 and 255. Invalid keycode: \(keycode)")
            }
        }
        if let delay = delay {
            guard delay >= 0 else {
                throw ValidationError("Delay must be non-negative.")
            }
            guard delay <= 5.0 else {
                throw ValidationError("Delay must not exceed 5 seconds.")
            }
        }
        guard keySequence.count <= 100 else {
            throw ValidationError("Key sequence must not exceed 100 keys.")
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        guard !keySequence.isEmpty else {
            logger.info().log("Empty key sequence: no-op")
            return
        }

        let keyDelay = delay ?? 0.1

        logger.info().log("Pressing key sequence: \(keySequence)")
        logger.info().log("Delay between keys: \(keyDelay) seconds")

        var events: [FBSimulatorHIDEvent] = []
        for (index, keycode) in keySequence.enumerated() {
            events.append(.shortKeyPress(UInt32(keycode)))
            if index < keySequence.count - 1 && keyDelay > 0 {
                events.append(.delay(keyDelay))
            }
        }

        try await HIDInteractor
            .performHIDEvent(
                FBSimulatorHIDEvent.composite(events),
                for: simulatorUDID,
                logger: logger
            )

        logger.info().log("Key sequence completed successfully")
    }
}
