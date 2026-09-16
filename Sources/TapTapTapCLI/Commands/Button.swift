import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `HIDButtonType` (common/types.py:111-116). Raw values match idb's spellings exactly;
/// `FBSimulatorHIDButton`'s raw values (1-5) already match idb's enum declaration order, so this
/// is a rename, not a remap (docs/IDB-COMPAT.md §2/§7).
enum ButtonType: String, CaseIterable, ExpressibleByArgument {
    case applePay = "APPLE_PAY"
    case home = "HOME"
    case lock = "LOCK"
    case sideButton = "SIDE_BUTTON"
    case siri = "SIRI"
    
    var hidButton: FBSimulatorHIDButton {
        switch self {
        case .applePay:
            return FBSimulatorHIDButton(rawValue: 1)! // FBSimulatorHIDButtonApplePay
        case .home:
            return FBSimulatorHIDButton(rawValue: 2)! // FBSimulatorHIDButtonHomeButton
        case .lock:
            return FBSimulatorHIDButton(rawValue: 3)! // FBSimulatorHIDButtonLock
        case .sideButton:
            return FBSimulatorHIDButton(rawValue: 4)! // FBSimulatorHIDButtonSideButton
        case .siri:
            return FBSimulatorHIDButton(rawValue: 5)! // FBSimulatorHIDButtonSiri
        }
    }
    
    var description: String {
        switch self {
        case .applePay:
            return "Apple Pay button"
        case .home:
            return "Home button"
        case .lock:
            return "Lock/Power button"
        case .sideButton:
            return "Side button"
        case .siri:
            return "Siri button"
        }
    }
}

struct Button: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "button",
        abstract: "A single press of a button",
        discussion: """
        Available buttons: APPLE_PAY, HOME, LOCK, SIDE_BUTTON, SIRI

        Examples:
          taptaptap ui button HOME --udid SIMULATOR_UDID
          taptaptap ui button LOCK --duration 2.0 --udid SIMULATOR_UDID
          taptaptap ui button SIRI --udid SIMULATOR_UDID
        """
    )

    @Argument(help: "The button name.")
    var buttonType: ButtonType

    @Option(name: .customLong("duration"), help: "Press duration.")
    var duration: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        // Validate duration if provided
        if let duration = duration {
            guard duration > 0 else {
                throw ValidationError("Duration must be greater than 0.")
            }
            guard duration <= 10.0 else {
                throw ValidationError("Duration must not exceed 10 seconds.")
            }
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)

        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        logger.info().log("Pressing \(buttonType.description)")
        if let duration = duration {
            logger.info().log("Duration: \(duration) seconds")
        }

        // Create button HID event
        let buttonEvent: FBSimulatorHIDEvent
        
        if let duration = duration {
            // For duration-based presses, we need to create separate down/up events with delay
            let buttonDownEvent = FBSimulatorHIDEvent.button(direction: .down, button: buttonType.hidButton)
            let delayEvent = FBSimulatorHIDEvent.delay(duration)
            let buttonUpEvent = FBSimulatorHIDEvent.button(direction: .up, button: buttonType.hidButton)

            buttonEvent = FBSimulatorHIDEvent.composite([
                buttonDownEvent,
                delayEvent,
                buttonUpEvent
            ])
        } else {
            // Simple short button press
            buttonEvent = FBSimulatorHIDEvent.shortButtonPress(buttonType.hidButton)
        }
        
        // Perform the button event
        try await HIDInteractor
            .performHIDEvent(
                buttonEvent,
                for: simulatorUDID,
                logger: logger
            )
        
        logger.info().log("\(buttonType.description) press completed successfully")
    }
} 
