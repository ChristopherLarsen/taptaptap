import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui pinch <x> <y> <scale> [--duration] [--radius]` (hid.py:235-268). Builds a
/// `.pinchAt(...)` two-finger-touch composite and sends it — see docs/IDB-COMPAT.md §2.
struct Pinch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pinch",
        abstract: "Perform a pinch gesture"
    )

    @Argument(help: "X coordinate of pinch center.")
    var x: Double

    @Argument(help: "Y coordinate of pinch center.")
    var y: Double

    @Argument(help: "Scale factor (>1.0 = zoom in, <1.0 = zoom out).")
    var scale: Double

    @Option(name: .customLong("duration"), help: "Duration in seconds.")
    var duration: Double = 0.5

    @Option(name: .customLong("radius"), help: "Initial finger distance from center in pixels.")
    var radius: Double = 100.0

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        logger.info().log("Performing pinch at (\(x), \(y)), scale: \(scale)")

        let physicalCenter = try await OrientationAwareCoordinates.translate(
            point: (x: x, y: y),
            for: simulatorUDID,
            logger: logger
        )

        let event = FBSimulatorHIDEvent.pinchAt(
            x: physicalCenter.x, y: physicalCenter.y, scale: scale, duration: duration, radius: radius)

        try await HIDInteractor.performHIDEvent(event, for: simulatorUDID, logger: logger)

        logger.info().log("Pinch gesture completed successfully")
    }
}
