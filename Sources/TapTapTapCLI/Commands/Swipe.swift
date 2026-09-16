import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui swipe <x_start> <y_start> <x_end> <y_end> [--duration] [--delta]` (hid.py:191-232).
/// Extras kept: --pre-delay, --post-delay (idb has none).
struct Swipe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipe",
        abstract: "Swipe from one point to another point"
    )

    @Argument(help: "The X coordinate of the swipe start point.")
    var xStart: Double

    @Argument(help: "The Y coordinate of the swipe start point.")
    var yStart: Double

    @Argument(help: "The X coordinate of the swipe end point.")
    var xEnd: Double

    @Argument(help: "The Y coordinate of the swipe end point.")
    var yEnd: Double

    @Option(name: .customLong("duration"), help: "Swipe duration.")
    var duration: Double?

    @Option(name: .customLong("delta"), help: "Delta in points between every touch point on the line between start and end points.")
    var delta: Double?

    @Option(name: .customLong("pre-delay"), help: "Delay before starting the swipe in seconds.")
    var preDelay: Double?

    @Option(name: .customLong("post-delay"), help: "Delay after completing the swipe in seconds.")
    var postDelay: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        guard xStart >= 0, yStart >= 0, xEnd >= 0, yEnd >= 0 else {
            throw ValidationError("Coordinates must be non-negative values.")
        }
        if let duration {
            guard duration > 0 else {
                throw ValidationError("Duration must be greater than 0.")
            }
        }
        if let delta {
            guard delta > 0 else {
                throw ValidationError("Delta must be greater than 0.")
            }
        }
        guard xStart != xEnd || yStart != yEnd else {
            throw ValidationError("Start and end points must be different.")
        }
        if let preDelay {
            guard preDelay >= 0 && preDelay <= 10.0 else {
                throw ValidationError("Pre-delay must be between 0 and 10 seconds.")
            }
        }
        if let postDelay {
            guard postDelay >= 0 && postDelay <= 10.0 else {
                throw ValidationError("Post-delay must be between 0 and 10 seconds.")
            }
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let swipeDuration = duration ?? 1.0
        let swipeDelta = delta ?? 50.0

        logger.info().log("Performing swipe from (\(xStart), \(yStart)) to (\(xEnd), \(yEnd))")
        logger.info().log("Duration: \(swipeDuration)s, Delta: \(swipeDelta)px")

        let physicalPoints = try await OrientationAwareCoordinates.translateBatch(
            points: [(x: xStart, y: yStart), (x: xEnd, y: yEnd)],
            for: simulatorUDID,
            logger: logger
        )
        let physicalStart = physicalPoints[0]
        let physicalEnd = physicalPoints[1]

        var events: [FBSimulatorHIDEvent] = []

        if let preDelay, preDelay > 0 {
            logger.info().log("Pre-delay: \(preDelay)s")
            events.append(FBSimulatorHIDEvent.delay(preDelay))
        }

        let swipeEvent = FBSimulatorHIDEvent.swipe(
            physicalStart.x,
            yStart: physicalStart.y,
            xEnd: physicalEnd.x,
            yEnd: physicalEnd.y,
            delta: swipeDelta,
            duration: swipeDuration
        )
        events.append(swipeEvent)

        if let postDelay, postDelay > 0 {
            logger.info().log("Post-delay: \(postDelay)s")
            events.append(FBSimulatorHIDEvent.delay(postDelay))
        }

        let finalEvent = events.count == 1 ? events[0] : FBSimulatorHIDEvent.composite(events)

        try await HIDInteractor
            .performHIDEvent(
                finalEvent,
                for: simulatorUDID,
                logger: logger
            )

        logger.info().log("Swipe gesture completed successfully")
    }
}
