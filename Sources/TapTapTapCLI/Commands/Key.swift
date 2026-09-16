import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui key <key> [--duration] [--shift] [--control] [--option] [--command] [--tab]`
/// (hid.py:100-150). Modifier keycodes match idb's own MODIFIER_KEYCODES
/// (idb/common/hid.py:90-97): shift=225, control=224, option=226, command=227, tab=43.
/// Modifiers are pressed down in the order shift/control/option/command/tab were requested by
/// idb's own `key_press_with_modifiers_to_events`, then released in reverse (LIFO), matching
/// docs/IDB-COMPAT.md §2/§7.
struct Key: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key",
        abstract: "A short press of a keycode with optional keyboard modifiers",
        discussion: """
        Press individual keys using their HID keycode values.

        Common keycodes:
          40 - Return/Enter
          42 - Backspace
          43 - Tab
          44 - Space
          58-67 - F1-F10
          224-231 - Modifier keys (Ctrl, Shift, Alt, etc.)

        Examples:
          taptaptap ui key 40 --udid SIMULATOR_UDID                    # Press Enter
          taptaptap ui key 44 --udid SIMULATOR_UDID                    # Press Space
          taptaptap ui key 42 --duration 1.0 --udid SIMULATOR_UDID     # Hold Backspace for 1 second
          taptaptap ui key 4 --command --udid SIMULATOR_UDID           # Cmd+A
        """
    )

    private static let controlKeycode: UInt32 = 224
    private static let shiftKeycode: UInt32 = 225
    private static let optionKeycode: UInt32 = 226
    private static let commandKeycode: UInt32 = 227
    private static let tabModifierKeycode: UInt32 = 43

    @Argument(help: "The HID keycode to press (0-255).")
    var key: Int

    @Option(name: .customLong("duration"), help: "Press duration.")
    var duration: Double?

    @Flag(name: .customLong("shift"), help: "Hold Shift modifier.")
    var shift: Bool = false

    @Flag(name: .customLong("control"), help: "Hold Control modifier.")
    var control: Bool = false

    @Flag(name: .customLong("option"), help: "Hold Option/Alt modifier.")
    var option: Bool = false

    @Flag(name: .customLong("command"), help: "Hold Command/GUI modifier.")
    var command: Bool = false

    @Flag(name: .customLong("tab"), help: "Hold Tab modifier (used in iOS Full Keyboard Access).")
    var tab: Bool = false

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        guard key >= 0 && key <= 255 else {
            throw ValidationError("Keycode must be between 0 and 255.")
        }
        if let duration = duration {
            guard duration > 0 else {
                throw ValidationError("Duration must be greater than 0.")
            }
            guard duration <= 10.0 else {
                throw ValidationError("Duration must not exceed 10 seconds.")
            }
        }
    }

    private var modifierKeycodes: [UInt32] {
        var modifiers: [UInt32] = []
        if control { modifiers.append(Self.controlKeycode) }
        if option { modifiers.append(Self.optionKeycode) }
        if shift { modifiers.append(Self.shiftKeycode) }
        if command { modifiers.append(Self.commandKeycode) }
        if tab { modifiers.append(Self.tabModifierKeycode) }
        return modifiers
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        logger.info().log("Pressing key with keycode: \(key)")
        if let duration = duration {
            logger.info().log("Duration: \(duration) seconds")
        }

        let modifiers = modifierKeycodes
        let keyEvent: FBSimulatorHIDEvent

        if !modifiers.isEmpty {
            var events: [FBSimulatorHIDEvent] = modifiers.map { .keyboard(direction: .down, keyCode: $0) }
            events.append(.keyboard(direction: .down, keyCode: UInt32(key)))
            if let duration {
                events.append(.delay(duration))
            }
            events.append(.keyboard(direction: .up, keyCode: UInt32(key)))
            events.append(contentsOf: modifiers.reversed().map { .keyboard(direction: .up, keyCode: $0) })
            keyEvent = .composite(events)
        } else if let duration = duration {
            keyEvent = FBSimulatorHIDEvent.composite([
                .keyboard(direction: .down, keyCode: UInt32(key)),
                .delay(duration),
                .keyboard(direction: .up, keyCode: UInt32(key))
            ])
        } else {
            keyEvent = FBSimulatorHIDEvent.shortKeyPress(UInt32(key))
        }

        try await HIDInteractor
            .performHIDEvent(
                keyEvent,
                for: simulatorUDID,
                logger: logger
            )

        logger.info().log("Key press completed successfully")
    }
}
