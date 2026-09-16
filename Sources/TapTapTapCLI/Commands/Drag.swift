import TapTapTapArguments
import Foundation

/// Extra (no idb equivalent): a low-level point-to-point drag. Coordinates are idb-shaped
/// positionals (previously --start-x/--start-y/--end-x/--end-y flags) for consistency with the
/// rest of the `ui` group.
struct Drag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Perform a low-level point-to-point drag using explicit touch move events."
    )

    private static let defaultDuration: TimeInterval = 0.6
    private static let defaultSteps = 60
    private static let maxSteps = 1_000
    private static let initialHold: TimeInterval = 0.05
    private static let finalHold: TimeInterval = 0.05

    @Argument(help: "The X coordinate of the starting point.")
    var xStart: Double

    @Argument(help: "The Y coordinate of the starting point.")
    var yStart: Double

    @Argument(help: "The X coordinate of the ending point.")
    var xEnd: Double

    @Argument(help: "The Y coordinate of the ending point.")
    var yEnd: Double

    @Option(name: .customLong("duration"), help: "Duration of the drag movement in seconds.")
    var duration: Double = Self.defaultDuration

    @Option(name: .customLong("steps"), help: "Number of touch move events to emit during the drag.")
    var steps: Int = Self.defaultSteps

    @Option(name: .customLong("pre-delay"), help: "Delay before starting the drag in seconds.")
    var preDelay: Double?

    @Option(name: .customLong("post-delay"), help: "Delay after completing the drag in seconds.")
    var postDelay: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        guard xStart >= 0, yStart >= 0, xEnd >= 0, yEnd >= 0 else {
            throw ValidationError("Coordinates must be non-negative values.")
        }
        guard xStart != xEnd || yStart != yEnd else {
            throw ValidationError("Start and end points must be different.")
        }
        guard duration > 0 else {
            throw ValidationError("Duration must be greater than 0.")
        }
        guard (1...Self.maxSteps).contains(steps) else {
            throw ValidationError("Steps must be between 1 and \(Self.maxSteps).")
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

        logger.info().log("Performing low-level drag from (\(xStart), \(yStart)) to (\(xEnd), \(yEnd))")
        logger.info().log("Duration: \(duration)s, steps: \(steps)")

        if let preDelay, preDelay > 0 {
            logger.info().log("Pre-delay: \(preDelay)s")
            try await Task.sleep(for: .seconds(preDelay))
        }

        let physicalPoints = try await OrientationAwareCoordinates.translateBatch(
            points: [(x: xStart, y: yStart), (x: xEnd, y: yEnd)],
            for: simulatorUDID,
            logger: logger
        )

        try await HIDInteractor.performCompositeDrag(
            from: physicalPoints[0],
            to: physicalPoints[1],
            duration: duration,
            steps: steps,
            initialHold: Self.initialHold,
            finalHold: Self.finalHold,
            for: simulatorUDID,
            logger: logger
        )

        if let postDelay, postDelay > 0 {
            logger.info().log("Post-delay: \(postDelay)s")
            try await Task.sleep(for: .seconds(postDelay))
        }

        logger.info().log("Low-level drag completed successfully")
    }
}
