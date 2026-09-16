import TapTapTapArguments
import Foundation
import TapTapTapSimulator
@preconcurrency import TapTapTapCore

/// idb: `screenshot <dest_path>` (screenshot.py:19-49). Changed from taptaptap's old `--output`
/// option (with a generated default filename) to idb's required positional, including `-` for
/// stdout.
struct Screenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Take a Screenshot of the Target"
    )

    @Argument(help: "The destination file path to write to, or - (dash) to write to stdout.")
    var destPath: String

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    func run() async throws {
        let logger = AxeLogger()
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(udid, logger: logger)

        let simulatorSet = try await getSimulatorSet(deviceSetPath: nil, logger: logger, reporter: EmptyEventReporter.shared)
        guard let targetSimulator = simulatorSet.allSimulators.first(where: { $0.udid == simulatorUDID }) else {
            throw CLIError.simulatorNotFound(udid: simulatorUDID)
        }

        guard targetSimulator.state == .booted else {
            let stateDescription = FBiOSTargetStateStringFromState(targetSimulator.state)
            throw CLIError(errorDescription: "Simulator \(simulatorUDID) is not booted. Current state: \(stateDescription)")
        }

        let screenshotData = try await VideoFrameUtilities.captureScreenshotData(from: targetSimulator)

        if destPath == "-" {
            FileHandle.standardOutput.write(screenshotData)
            return
        }

        let outputURL = try prepareOutputURL(simulator: targetSimulator)
        try screenshotData.write(to: outputURL)

        FileHandle.standardError.write(Data("Screenshot saved to \(outputURL.path)\n".utf8))
        print(outputURL.path)
    }

    private func prepareOutputURL(simulator: FBSimulator) throws -> URL {
        let fileManager = FileManager.default
        let resolvedPath = (destPath as NSString).expandingTildeInPath

        let baseURL: URL
        if resolvedPath.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: resolvedPath)
        } else {
            baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(resolvedPath)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: baseURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let timestamp = Self.formatTimestamp(Date())
            let filename = "Simulator Screenshot - \(simulator.name) - \(timestamp).png"
            let directoryURL = baseURL
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            return directoryURL.appendingPathComponent(filename)
        }

        let directoryURL = baseURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        if fileManager.fileExists(atPath: baseURL.path) {
            var existingIsDirectory: ObjCBool = false
            fileManager.fileExists(atPath: baseURL.path, isDirectory: &existingIsDirectory)
            if existingIsDirectory.boolValue {
                throw CLIError(errorDescription: "Output path \(baseURL.path) is a directory. Provide a file name or point to a different location.")
            }
            try fileManager.removeItem(at: baseURL)
        }

        return baseURL
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}
