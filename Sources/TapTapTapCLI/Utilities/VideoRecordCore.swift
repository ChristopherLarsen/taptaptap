import TapTapTapArguments
import Foundation
import TapTapTapSimulator
@preconcurrency import TapTapTapCore
import AVFoundation

/// Shared implementation behind `video`, `record-video`, and `record video` — idb's `video`
/// command (video.py:23-43, `aliases=["record-video"]`) plus the `record` CommandGroup wrapping it
/// (main.py:233-238). Three thin command structs share this one recording implementation; see
/// docs/IDB-COMPAT.md §7 for why aliasing is done this way instead of adding alias support to the
/// parser engine.
enum VideoRecordCore {
    struct Options {
        var udid: String?
        var fps: Int = 10
        var quality: Int = 80
        var scale: Double = 1.0
        var outputFile: String
        /// Stop and finalize automatically after this many seconds — no signal required. Not an
        /// idb option; added for F1 (TESTING.md): agents that background `record-video` inside
        /// one shell call and never signal it left corrupt, moov-less MP4s (evidence:
        /// evidence-testing/layer3/runs/claude-T4).
        var duration: Double?
    }

    static func validate(_ options: Options) throws {
        guard options.fps >= 1 && options.fps <= 30 else {
            throw ValidationError("FPS must be between 1 and 30")
        }
        guard options.quality >= 1 && options.quality <= 100 else {
            throw ValidationError("Quality must be between 1 and 100")
        }
        guard options.scale >= 0.1 && options.scale <= 1.0 else {
            throw ValidationError("Scale must be between 0.1 and 1.0")
        }
        if let duration = options.duration {
            guard duration > 0 && duration <= 3600 else {
                throw ValidationError("Duration must be greater than 0 and at most 3600 seconds")
            }
        }
    }

    static func run(_ options: Options) async throws {
        let logger = AxeLogger()
        try await setupStandalone(logger: logger)
        try await performGlobalSetup(logger: logger)
        let simulatorUDID = try await resolveSimulatorUDID(options.udid, logger: logger)

        let simulatorSet = try await getSimulatorSet(deviceSetPath: nil, logger: logger, reporter: EmptyEventReporter.shared)
        guard let targetSimulator = simulatorSet.allSimulators.first(where: { $0.udid == simulatorUDID }) else {
            throw CLIError.simulatorNotFound(udid: simulatorUDID)
        }
        guard targetSimulator.state == .booted else {
            let stateDescription = FBiOSTargetStateStringFromState(targetSimulator.state)
            throw CLIError(errorDescription: "Simulator \(simulatorUDID) is not booted. Current state: \(stateDescription)")
        }

        let outputURL = try prepareOutputURL(options.outputFile)
        FileHandle.standardError.write(Data("Recording simulator \(targetSimulator.udid) to \(outputURL.path)\n".utf8))
        if let duration = options.duration {
            FileHandle.standardError.write(Data("Recording for \(duration)s; will stop and save automatically (Ctrl+C also stops early)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("Press Ctrl+C to stop recording\n".utf8))
        }

        let cancellationFlag = CancellationFlag()
        // SIGHUP: a backgrounded recorder (`record-video x.mp4 &` inside one shell call) can be
        // orphaned when its controlling shell exits, which delivers SIGHUP, not SIGINT/SIGTERM.
        // Without this, SIGHUP's default action terminates the process before `finish()` writes
        // the moov atom (F1, TESTING.md).
        let signalObserver = SignalObserver(signals: [SIGINT, SIGTERM, SIGHUP]) {
            Task { await cancellationFlag.cancel() }
        }
        defer { signalObserver.invalidate() }

        do {
            try await recordVideo(
                simulator: targetSimulator,
                outputURL: outputURL,
                fps: options.fps,
                quality: options.quality,
                scale: options.scale,
                duration: options.duration,
                cancellationFlag: cancellationFlag
            )
            FileHandle.standardError.write(Data("Recording saved to \(outputURL.path)\n".utf8))
            print(outputURL.path)
        } catch {
            throw CLIError(errorDescription: "Failed to record video: \(error.localizedDescription)")
        }
    }

    private static func setupStandalone(logger: AxeLogger) async throws {
        do {
            let developerDirectory = try FBXcodeDirectory.resolveDeveloperDirectory()
            if developerDirectory.isEmpty {
                throw CLIError(errorDescription: "TapTapTap could not find an active Xcode installation. Select Xcode with `xcode-select` or set `DEVELOPER_DIR`, then try again.")
            }
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError(errorDescription: "TapTapTap could not find an active Xcode installation. Select Xcode with `xcode-select` or set `DEVELOPER_DIR`, then try again.")
        }
        do {
            try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
        } catch {
            throw CLIError(errorDescription: "TapTapTap could not load simulator support from the selected Xcode installation. Confirm Xcode 26 or later is selected and try again.")
        }
    }

    private static func recordVideo(
        simulator: FBSimulator,
        outputURL: URL,
        fps: Int,
        quality: Int,
        scale: Double,
        duration: Double?,
        cancellationFlag: CancellationFlag
    ) async throws {
        let initialFrameData = try await VideoFrameUtilities.captureScreenshotData(from: simulator)
        guard let initialImage = VideoFrameUtilities.makeCGImage(from: initialFrameData) else {
            throw CLIError(errorDescription: "Failed to decode simulator screenshot")
        }

        let dimensions = VideoFrameUtilities.computeDimensions(for: initialImage, scale: scale)
        let recorder = try H264StreamRecorder(
            outputURL: outputURL,
            width: dimensions.width,
            height: dimensions.height,
            fps: fps,
            quality: quality
        )
        defer { recorder.invalidate() }

        let frameInterval = 1.0 / Double(fps)
        var frameCount: Int64 = 1
        var lastLogFrame: Int64 = 0
        let startTime = Date()
        let deadline = duration.map { startTime.addingTimeInterval($0) }
        var lastPresentationTime = CMTime.zero

        try recorder.append(image: initialImage, presentationTime: .zero)
        let writerStartTime = Date()

        while true {
            if Task.isCancelled { break }
            if await cancellationFlag.isCancelled() { break }
            if let deadline, Date() >= deadline { break }

            let frameStart = Date()

            do {
                let frameData = try await VideoFrameUtilities.captureScreenshotData(from: simulator)
                guard let cgImage = VideoFrameUtilities.makeCGImage(from: frameData) else {
                    FileHandle.standardError.write(Data("Unable to decode screenshot frame\n".utf8))
                    continue
                }

                let now = Date()
                var presentationTime = CMTime(seconds: now.timeIntervalSince(writerStartTime), preferredTimescale: 600)
                if presentationTime <= lastPresentationTime {
                    presentationTime = CMTimeAdd(lastPresentationTime, CMTime(value: 1, timescale: 600))
                }

                try recorder.append(image: cgImage, presentationTime: presentationTime)
                lastPresentationTime = presentationTime
                frameCount += 1

                if frameCount - lastLogFrame >= Int64(fps) {
                    lastLogFrame = frameCount
                    let elapsed = Date().timeIntervalSince(startTime)
                    let actualFPS = Double(frameCount) / max(elapsed, 0.0001)
                    FileHandle.standardError.write(Data(String(format: "Captured %lld frames (%.1f FPS actual)\n", frameCount, actualFPS).utf8))
                }
            } catch {
                FileHandle.standardError.write(Data("Error capturing frame: \(error.localizedDescription)\n".utf8))
            }

            let elapsed = Date().timeIntervalSince(frameStart)
            let sleepTime = frameInterval - elapsed
            if sleepTime > 0 {
                try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }

        try await recorder.finish()
    }

    private static func prepareOutputURL(_ outputFile: String) throws -> URL {
        let fileManager = FileManager.default
        let resolvedPath = (outputFile as NSString).expandingTildeInPath

        let baseURL: URL
        if resolvedPath.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: resolvedPath)
        } else {
            baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(resolvedPath)
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
}
