import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// Extra (no idb equivalent): low-level touch down/up. Coordinates are idb-shaped positionals
/// (previously -x/-y flags) for consistency with the rest of the `ui` group.
struct Touch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Perform precise touch down/up events at specific coordinates.",
        discussion: """
        Perform low-level touch events for advanced gesture control.
        You can either perform a single touch down, touch up, or both.

        Examples:
          taptaptap ui touch 100 200 --down --udid SIMULATOR_UDID        # Touch down at (100, 200)
          taptaptap ui touch 100 200 --up --udid SIMULATOR_UDID          # Touch up at (100, 200)
          taptaptap ui touch 100 200 --down --up --udid SIMULATOR_UDID   # Touch down then up (like tap)
          taptaptap ui touch 100 200 --down --up --delay 1.0 --udid SIMULATOR_UDID # Long press (hold for 1s)
        """
    )

    @Argument(help: "The X coordinate of the touch point.")
    var x: Double

    @Argument(help: "The Y coordinate of the touch point.")
    var y: Double

    @Flag(name: .customLong("down"), help: "Perform touch down event.")
    var touchDown: Bool = false

    @Flag(name: .customLong("up"), help: "Perform touch up event.")
    var touchUp: Bool = false

    @Option(name: .customLong("delay"), help: "Delay between touch down and up events in seconds (if both are specified).")
    var delay: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        guard x >= 0, y >= 0 else {
            throw ValidationError("Coordinates must be non-negative values.")
        }
        guard touchDown || touchUp else {
            throw ValidationError("At least one of --down or --up must be specified.")
        }
        if let delay = delay {
            guard delay >= 0 else {
                throw ValidationError("Delay must be non-negative.")
            }
            guard delay <= 10.0 else {
                throw ValidationError("Delay must not exceed 10 seconds.")
            }
            guard touchDown && touchUp else {
                throw ValidationError("Delay can only be used when both --down and --up are specified.")
            }
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        logger.info().log("Performing touch events at (\(x), \(y))")

        let physicalPoint = try await OrientationAwareCoordinates.translate(
            point: (x: x, y: y),
            for: simulatorUDID,
            logger: logger
        )

        var primitives: [HIDBrokerPrimitive] = []
        if touchDown && touchUp {
            let touchDelay = delay ?? TapTiming.defaultHoldDuration

            logger.info().log("Touch down")
            primitives.append(.touch(.down, x: physicalPoint.x, y: physicalPoint.y))

            if touchDelay > 0 {
                logger.info().log("Delay: \(touchDelay) seconds")
                primitives.append(.delay(touchDelay))
            }

            logger.info().log("Touch up")
            primitives.append(.touch(.up, x: physicalPoint.x, y: physicalPoint.y))
        } else if touchDown {
            logger.info().log("Touch down")
            primitives.append(.touch(.down, x: physicalPoint.x, y: physicalPoint.y))
        } else {
            logger.info().log("Touch up")
            primitives.append(.touch(.up, x: physicalPoint.x, y: physicalPoint.y))
        }

        try HIDBroker.sendTouchPrimitives(primitives, simulatorUDID: simulatorUDID)

        logger.info().log("Touch events completed successfully")
    }
}
