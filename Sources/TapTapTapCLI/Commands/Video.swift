import TapTapTapArguments
import Foundation

/// idb: `video <output_file>` (video.py:23-43), idb's primary name for this command (aliased to
/// `record-video`, and wrapped by a `record` group as `record video` — see Video.swift's sibling
/// structs `RecordVideo` and `Record`). All three share `VideoRecordCore`.
struct Video: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "video",
        abstract: "Record the target's screen to a mp4 video file"
    )

    @Argument(help: "mp4 file to output the video to.")
    var outputFile: String

    @Option(name: .customLong("udid"), help: "The UDID of the simulator. Defaults to the sole booted simulator.")
    var udid: String?

    @Option(help: "Frames per second (1-30, default: 10)")
    var fps: Int = 10

    @Option(help: "Quality factor (1-100) controlling bitrate (default: 80)")
    var quality: Int = 80

    @Option(help: "Scale factor (0.1-1.0, default: 1.0)")
    var scale: Double = 1.0

    @Option(help: "Stop and save automatically after this many seconds (greater than 0, up to 3600); no signal needed. Not an idb option.")
    var duration: Double?

    func validate() throws {
        try VideoRecordCore.validate(VideoRecordCore.Options(udid: udid, fps: fps, quality: quality, scale: scale, outputFile: outputFile, duration: duration))
    }

    func run() async throws {
        try await VideoRecordCore.run(VideoRecordCore.Options(udid: udid, fps: fps, quality: quality, scale: scale, outputFile: outputFile, duration: duration))
    }
}
