import TapTapTapArguments
import Foundation
import TapTapTapCore
import TapTapTapSimulator

/// idb: `ui text <text>` (hid.py:174-188). Extras kept: --stdin, --file (idb's `text` only takes
/// the positional). Renamed from taptaptap's old `type` command to idb's `text`.
struct Text: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Input text",
        discussion: """
        Input Methods:
        1. Direct text: taptaptap ui text "Hello World" --udid UDID
        2. From stdin: echo "Hello World!" | taptaptap ui text --stdin --udid UDID
        3. From file: taptaptap ui text --file text.txt --udid UDID

        Examples:
        • Simple text: taptaptap ui text "Hello World" --udid UDID
        • With spaces: taptaptap ui text "Hello, how are you?" --udid UDID
        • Special characters: taptaptap ui text 'Hello!' --udid UDID

        Shell Escaping Tips:
        • Use double quotes for text with spaces: "Hello World"
        • Use single quotes for text with special characters: 'Hello!'
        • For complex text or automation, prefer --stdin or --file methods

        Character Support:
        • Only US keyboard characters are supported via HID keycodes
        • Supported: A-Z, a-z, 0-9, and symbols: !@#$%^&*()_+-={}[]|\\:";'<>?,./`~
        • Not supported: International characters (£€¥), accented letters (éñü), etc.
        • This is a limitation of the underlying HID keyboard protocol

        Note: iOS may apply smart punctuation spacing to some characters.
        """
    )

    @Argument(help: "Text to input. Use quotes for text with spaces or special characters.")
    var text: String?

    @Flag(name: .customLong("stdin"), help: "Read text from standard input.")
    var useStdin: Bool = false

    @Option(name: .customLong("file"), help: "Read text from the specified file.")
    var inputFile: String?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func validate() throws {
        let sourceCount = [text != nil, useStdin, inputFile != nil].filter { $0 }.count
        if sourceCount > 1 {
            throw ValidationError("Please specify only one input source: text argument, --stdin, or --file.")
        }
        if sourceCount == 0 {
            throw ValidationError("No input provided. Provide text as argument, or use --stdin, or --file.")
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let inputText: String
        switch (text, useStdin, inputFile) {
        case (let positionalText?, false, nil):
            inputText = positionalText
            logger.info().log("Using positional text input (\(inputText.count) characters)")
        case (nil, true, nil):
            logger.info().log("Reading text from standard input...")
            inputText = readFromStdin()
            logger.info().log("Read \(inputText.count) characters from stdin")
        case (nil, false, let file?):
            logger.info().log("Reading text from file: \(file)")
            inputText = try readFromFile(file)
            logger.info().log("Read \(inputText.count) characters from file")
        case (nil, false, nil):
            throw ValidationError("No input provided. Provide text as argument, or use --stdin, or --file.")
        default:
            throw ValidationError("Invalid input configuration.")
        }

        guard TextToHIDEvents.validateText(inputText) else {
            let unsupportedChars = inputText.compactMap { char in
                let keyEvent = KeyEvent.keyCodeForString(String(char))
                return keyEvent.keyCode == 0 ? char : nil
            }
            let errorMessage = """
                Unsupported characters found: \(unsupportedChars.map { "'\($0)'" }.joined(separator: ", "))

                Only US keyboard characters are supported via HID keycodes.
                Supported: A-Z, a-z, 0-9, and symbols: !@#$%^&*()_+-={}[]|\\:";'<>?,./`~
                """
            logger.error().log(errorMessage)
            throw TextToHIDEvents.TextConversionError.unsupportedCharacter(unsupportedChars.first!)
        }

        let hidEvents: [FBSimulatorHIDEvent]
        do {
            hidEvents = try TextToHIDEvents.convertTextToHIDEvents(inputText)
            logger.info().log("Successfully converted text to \(hidEvents.count) HID events")
        } catch let error as TextToHIDEvents.TextConversionError {
            logger.error().log("Text conversion failed: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error().log("Unexpected error during text conversion: \(error.localizedDescription)")
            throw error
        }

        logger.info().log("Performing HID event sequence for text typing")

        if !hidEvents.isEmpty {
            try await HIDInteractor
                .performHIDEvent(
                    .composite(hidEvents),
                    for: simulatorUDID,
                    logger: logger
                )
        }

        logger.info().log("Text typing completed successfully")
    }

    func readFromStdin() -> String {
        var input = ""
        while let line = readLine() {
            if !input.isEmpty {
                input += "\n"
            }
            input += line
        }
        return input
    }

    func readFromFile(_ filePath: String) throws -> String {
        do {
            return try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            throw ValidationError("Failed to read file '\(filePath)': \(error.localizedDescription)")
        }
    }
}
