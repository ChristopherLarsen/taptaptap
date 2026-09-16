import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui tap <x> <y> [--duration]` (hid.py:19-35). Extras kept: --id/--label/--value element
/// targeting (x/y become optional when one of those is given), --element-type, --wait-timeout,
/// --poll-interval, --tap-style, --pre-delay, --post-delay. See docs/IDB-COMPAT.md §2.
struct Tap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tap",
        abstract: "Tap a point on the screen, or locate an element by accessibility and tap its activation point."
    )

    @Argument(help: "The X coordinate.")
    var x: Double?

    @Argument(help: "The Y coordinate.")
    var y: Double?

    @Option(name: .customLong("duration"), help: "Press duration in seconds.")
    var duration: Double?

    @Option(name: [.customLong("id")], help: "Tap the activation point of the element matching AXUniqueId (accessibilityIdentifier). Ignored if <x> <y> are provided.")
    var elementID: String?

    @Option(name: [.customLong("label")], help: "Tap the activation point of the element matching AXLabel (accessibilityLabel). Ignored if <x> <y> are provided.")
    var elementLabel: String?

    @Option(name: [.customLong("value")], help: "Tap the activation point of the element matching AXValue (the current value of a control). Ignored if <x> <y> are provided.")
    var elementValue: String?

    @Option(name: [.customLong("element-type")], help: "Filter matches to elements of this accessibility type (e.g. Button, TextField, Switch). Narrows --id/--label/--value results when multiple elements match.")
    var elementType: String?

    @Option(name: .customLong("pre-delay"), help: "Delay before tapping in seconds.")
    var preDelay: Double?

    @Option(name: .customLong("post-delay"), help: "Delay after tapping in seconds.")
    var postDelay: Double?

    @Option(name: .customLong("tap-style"), help: "Tap event style: automatic uses physical touch for switches/toggles and simulator tap for other targets; simulator always uses FBSimulator tapAt; physical uses touch down/up.")
    var tapStyle: TapStyle?

    @Option(name: .customLong("wait-timeout"), help: "Maximum seconds to poll for the element before failing (0 = no waiting, default). Only applies to --id/--label/--value targeting.")
    var waitTimeout: Double = 0

    @Option(name: .customLong("poll-interval"), help: "Seconds between accessibility tree polls when --wait-timeout is active (default: 0.25).")
    var pollInterval: Double = 0.25

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        if x != nil || y != nil {
            guard let x, let y else {
                throw ValidationError("Both <x> and <y> must be provided together.")
            }
            guard x >= 0, y >= 0 else {
                throw ValidationError("Coordinates must be non-negative values.")
            }
        } else {
            let selectorCount = [elementID != nil, elementLabel != nil, elementValue != nil].filter { $0 }.count
            if selectorCount == 0 {
                throw ValidationError("Either provide both <x> <y>, or use --id/--label/--value to tap an element.")
            }
            if selectorCount > 1 {
                throw ValidationError("Use only one of --id, --label, or --value.")
            }
            if let elementID, elementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("--id must not be empty.")
            }
            if let elementLabel, elementLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("--label must not be empty.")
            }
            if let elementValue, elementValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("--value must not be empty.")
            }
        }

        if let duration {
            guard duration > 0 && duration <= 10.0 else {
                throw ValidationError("--duration must be between 0 and 10 seconds.")
            }
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

        guard waitTimeout >= 0 else {
            throw ValidationError("--wait-timeout must be non-negative.")
        }

        if waitTimeout > 0 {
            guard pollInterval > 0 else {
                throw ValidationError("--poll-interval must be greater than 0 when --wait-timeout is active.")
            }
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let resolution: TapResolution
        let resolvedDescription: String

        if let x, let y {
            resolution = TapResolution(point: (x: x, y: y), isSwitchLikeControl: false)
            resolvedDescription = "(\(x), \(y))"
        } else {
            let query: AccessibilityQuery
            if let elementID {
                query = .id(elementID)
            } else if let elementLabel {
                query = .label(elementLabel)
            } else if let elementValue {
                query = .value(elementValue)
            } else {
                throw CLIError(errorDescription: "Unexpected state: no coordinates and no element query.")
            }

            do {
                resolution = try await AccessibilityPoller.resolveWithPolling(
                    query: query,
                    simulatorUDID: simulatorUDID,
                    waitTimeout: waitTimeout,
                    pollInterval: pollInterval,
                    elementType: elementType,
                    logger: logger
                )
            } catch let error as ElementResolutionError {
                print("Warning: \(error.localizedDescription) No tap performed.", to: &standardError)
                throw error
            }

            resolvedDescription = "resolved tap point at (\(resolution.point.x), \(resolution.point.y))"
        }

        logger.info().log("Tapping at \(resolvedDescription)")

        let physicalPoint = try await OrientationAwareCoordinates.translate(
            point: resolution.point,
            for: simulatorUDID,
            logger: logger
        )

        switch resolvedTapStyle(for: resolution) {
        case .physical:
            // --duration isn't threaded into the physical touch-down/up path (a fixed hold
            // duration is used there); it fully applies to the .simulator style below.
            try await HIDInteractor.performPhysicalTap(
                at: physicalPoint,
                preDelay: preDelay,
                postDelay: postDelay,
                for: simulatorUDID,
                logger: logger
            )
        case .simulator:
            var events: [FBSimulatorHIDEvent] = []
            if let preDelay, preDelay > 0 {
                logger.info().log("Pre-delay: \(preDelay)s")
                events.append(.delay(preDelay))
            }
            if let duration {
                logger.info().log("Duration: \(duration)s")
                events.append(.tapAt(x: physicalPoint.x, y: physicalPoint.y, duration: duration))
            } else {
                events.append(.tapAt(x: physicalPoint.x, y: physicalPoint.y))
            }
            if let postDelay, postDelay > 0 {
                logger.info().log("Post-delay: \(postDelay)s")
                events.append(.delay(postDelay))
            }

            let finalEvent = events.count == 1 ? events[0] : FBSimulatorHIDEvent.composite(events)
            try await HIDInteractor.performHIDEvent(finalEvent, for: simulatorUDID, logger: logger)
        case .automatic:
            throw CLIError(errorDescription: "Unexpected tap style resolution.")
        }

        logger.info().log("Tap completed successfully")
        print("✓ Tap at \(resolvedDescription) completed successfully")
    }

    private func resolvedTapStyle(for resolution: TapResolution) -> TapStyle {
        switch tapStyle ?? .automatic {
        case .automatic:
            return resolution.isSwitchLikeControl ? .physical : .simulator
        case .simulator:
            return .simulator
        case .physical:
            return .physical
        }
    }
}
