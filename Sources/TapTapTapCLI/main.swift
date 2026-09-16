import TapTapTapArguments
import Foundation
import TapTapTapCore
import Darwin // For Darwin.exit()

// MARK: - Main Entry Point
@main
struct TapTapTap: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "taptaptap",
        abstract: "A utility to interact with iOS Simulators and extract accessibility information. If you know idb, use the same commands with `taptaptap` in place of `idb`.",
        version: VERSION,
        subcommands: [
            ListTargets.self,
            Describe.self,
            Screenshot.self,
            Video.self,
            RecordVideo.self,
            Record.self,
            Batch.self,
            HIDBrokerCommand.self,
            Ui.self,
            // Recognized idb commands outside taptaptap's kept scope: each fails with a one-line
            // `xcrun simctl` pointer instead of a generic "unknown command" error. §6 of
            // docs/IDB-COMPAT.md.
            InstallCommand.self,
            UninstallCommand.self,
            ListAppsCommand.self,
            LaunchCommand.self,
            TerminateCommand.self,
            OpenCommand.self,
            LogCommand.self,
            LocationCommand.self,
            BootCommand.self,
            ShutdownCommand.self,
            EraseCommand.self,
            CreateCommand.self,
            CloneCommand.self,
            DeleteCommand.self,
            DeleteAllCommand.self,
            ConnectCommand.self,
            DisconnectCommand.self,
            XctestCommand.self,
            CrashCommand.self,
            InstrumentsCommand.self,
            XctraceCommand.self,
            DapCommand.self,
            DebugserverCommand.self,
            FileCommand.self,
            FocusCommand.self,
            ApproveCommand.self,
            RevokeCommand.self,
            ContactsCommand.self,
            PhotosCommand.self,
            KeychainCommand.self,
            NotificationCommand.self,
            MemoryCommand.self,
            SettingsCommand.self,
            ShellCommand.self,
            FrameworkCommand.self,
            DsymCommand.self,
            DylibCommand.self,
            MediaCommand.self
        ]
    )
}
