import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui multi-tap <x> <y> [--count] [--duration] [--pause]` (hid.py:38-72). Implemented as
/// repeated `tapAt` events separated by `--pause` delays — the existing single-finger HID
/// primitive already supports this cheaply (see docs/IDB-COMPAT.md §2).
struct MultiTap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "multi-tap",
        abstract: "Multi Tap On the Screen (default: double tap)"
    )

    @Argument(help: "The X coordinate.")
    var x: Double

    @Argument(help: "The Y coordinate.")
    var y: Double

    @Option(name: .customLong("count"), help: "Number of taps (default: 2).")
    var count: Int = 2

    @Option(name: .customLong("duration"), help: "Press duration per tap, in seconds.")
    var duration: Double?

    @Option(name: .customLong("pause"), help: "Pause between taps in seconds (default: 0.1).")
    var pause: Double = 0.1

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        guard x >= 0, y >= 0 else {
            throw ValidationError("Coordinates must be non-negative values.")
        }
        guard count >= 1 else {
            throw ValidationError("--count must be at least 1.")
        }
        if let duration {
            guard duration > 0 && duration <= 10.0 else {
                throw ValidationError("--duration must be between 0 and 10 seconds.")
            }
        }
        guard pause >= 0 else {
            throw ValidationError("--pause must be non-negative.")
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let physicalPoint = try await OrientationAwareCoordinates.translate(
            point: (x: x, y: y),
            for: simulatorUDID,
            logger: logger
        )

        var events: [FBSimulatorHIDEvent] = []
        for tapIndex in 0..<count {
            if let duration {
                events.append(.tapAt(x: physicalPoint.x, y: physicalPoint.y, duration: duration))
            } else {
                events.append(.tapAt(x: physicalPoint.x, y: physicalPoint.y))
            }
            if tapIndex < count - 1 && pause > 0 {
                events.append(.delay(pause))
            }
        }

        logger.info().log("Multi-tapping (\(x), \(y)) \(count) time(s)")
        try await HIDInteractor.performHIDEvent(FBSimulatorHIDEvent.composite(events), for: simulatorUDID, logger: logger)
        print("✓ Multi-tap at (\(x), \(y)) completed successfully")
    }
}
