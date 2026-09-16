import TapTapTapArguments
import Foundation

/// idb: `video`'s declared alias `record-video` (video.py:33-34, `aliases = ["record-video"]`).
/// The parser engine has no alias list (docs/IDB-COMPAT.md §7), so this is a thin sibling of
/// `Video` sharing `VideoRecordCore`.
struct RecordVideo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record-video",
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
