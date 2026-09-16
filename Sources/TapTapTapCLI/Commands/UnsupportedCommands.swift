import TapTapTapArguments
import Foundation

/// idb commands outside the charter's kept scope (install/launch/xctest/devices/…). Recognized as
/// real subcommands — not a catch-all — so an agent typing idb muscle memory gets a one-line,
/// actionable pointer (exit 1) instead of a generic "unknown command" error. Each swallows any
/// positional arguments and a `--udid` so a full idb-shaped invocation doesn't also throw a
/// confusing "unknown option" error. See docs/IDB-COMPAT.md §6 for the full table and rationale.
private func unsupportedPointer(_ pointer: String) -> Never {
    FileHandle.standardError.write(Data("not supported by taptaptap; use: \(pointer)\n".utf8))
    exit(1)
}

private protocol UnsupportedIdbCommand: AsyncParsableCommand {
    static var pointer: String { get }
}

extension UnsupportedIdbCommand {
    func run() async throws {
        unsupportedPointer(Self.pointer)
    }
}

// MARK: - App lifecycle

struct InstallCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install an application")
    static let pointer = "xcrun simctl install <udid> <app-path>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct UninstallCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Uninstall an application")
    static let pointer = "xcrun simctl uninstall <udid> <bundle-id>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct ListAppsCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "list-apps", abstract: "List installed applications")
    static let pointer = "xcrun simctl listapps <udid>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct LaunchCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "launch", abstract: "Launch an application")
    static let pointer = "xcrun simctl launch <udid> <bundle-id>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct TerminateCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "terminate", abstract: "Terminate an application")
    static let pointer = "xcrun simctl terminate <udid> <bundle-id>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct OpenCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "open", abstract: "Open a URL")
    static let pointer = "xcrun simctl openurl <udid> <url>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

// MARK: - Logs, location, diagnostics

struct LogCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "log", abstract: "Stream logs")
    static let pointer = "xcrun simctl spawn <udid> log stream"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct LocationCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "location", abstract: "Set simulated location")
    static let pointer = "xcrun simctl location <udid> set <lat,lon>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

// MARK: - Target lifecycle (idb's boot/shutdown/erase/create/clone/delete are top-level, not `target …`)

struct BootCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "boot", abstract: "Boot a simulator")
    static let pointer = "xcrun simctl boot <udid>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct ShutdownCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "shutdown", abstract: "Shut down a simulator")
    static let pointer = "xcrun simctl shutdown <udid>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct EraseCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "erase", abstract: "Erase a simulator")
    static let pointer = "xcrun simctl erase <udid>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct CreateCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a simulator")
    static let pointer = "xcrun simctl create <name> <device-type> <runtime>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct CloneCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "clone", abstract: "Clone a simulator")
    static let pointer = "xcrun simctl clone <udid> <new-name>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DeleteCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a simulator")
    static let pointer = "xcrun simctl delete <udid>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DeleteAllCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "delete-all", abstract: "Delete all simulators")
    static let pointer = "xcrun simctl delete unavailable  (or: xcrun simctl erase all)"
    @Argument var rest: [String] = []
}

struct ConnectCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "connect", abstract: "Connect to a companion")
    static let pointer = "not applicable — taptaptap has no companion process; it talks to the simulator directly"
    @Argument var rest: [String] = []
}

struct DisconnectCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Disconnect a companion")
    static let pointer = "not applicable — taptaptap has no companion process; it talks to the simulator directly"
    @Argument var rest: [String] = []
}

// MARK: - Testing, tracing, debugging (out of the charter's kept scope)

struct XctestCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "xctest", abstract: "xctest operations")
    static let pointer = "Xcode's own test runner (xcodebuild test)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct CrashCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "crash", abstract: "Crash log operations")
    static let pointer = "xcrun simctl spawn <udid> log collect  (crash reports)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct InstrumentsCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "instruments", abstract: "Run instruments")
    static let pointer = "Xcode's Instruments app"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct XctraceCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "xctrace", abstract: "Run xctrace commands")
    static let pointer = "xctrace record"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DapCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "dap", abstract: "Debug Adapter Protocol")
    static let pointer = "Xcode's own debugger (not exposed as a CLI)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DebugserverCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "debugserver", abstract: "debugserver interactions")
    static let pointer = "lldb / Xcode's own debugger"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

// MARK: - Filesystem, app data, privacy

struct FileCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "file", abstract: "File operations on target")
    static let pointer = "xcrun simctl get_app_container <udid> <bundle-id>  (or direct access to the simulator's data directory)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct FocusCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "focus", abstract: "Focus the simulator window")
    static let pointer = "xcrun simctl ui <udid> ... (or click the Simulator app)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct ApproveCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "approve", abstract: "Approve a permission")
    static let pointer = "xcrun simctl privacy <udid> grant <service> <bundle-id>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct RevokeCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "revoke", abstract: "Revoke a permission")
    static let pointer = "xcrun simctl privacy <udid> revoke <service> <bundle-id>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct ContactsCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "contacts", abstract: "Contacts database operations on target")
    static let pointer = "xcrun simctl privacy <udid> grant contacts-full <bundle-id>  (or edit the simulator's AddressBook directly)"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct PhotosCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "photos", abstract: "Photos library operations on target")
    static let pointer = "xcrun simctl addmedia <udid> <path>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct KeychainCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "keychain", abstract: "Keychain operations")
    static let pointer = "xcrun simctl keychain <udid> reset"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct NotificationCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "notification", abstract: "Send a notification")
    static let pointer = "xcrun simctl push <udid> <bundle-id> <payload.apns>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct MemoryCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "memory", abstract: "Simulate a memory warning")
    static let pointer = "xcrun simctl spawn <udid> notifyutil -p com.apple.system.memorystatus_level_change"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct SettingsCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "settings", abstract: "Simulator settings")
    static let pointer = "xcrun simctl spawn <udid> defaults ..."
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct ShellCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "shell", abstract: "Interactive shell")
    static let pointer = "xcrun simctl spawn <udid> <command>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct FrameworkCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "framework", abstract: "framework commands")
    static let pointer = "not applicable — taptaptap ships as one signed binary, no dynamic framework installs"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DsymCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "dsym", abstract: "dsym commands")
    static let pointer = "not applicable — taptaptap doesn't install test bundles"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct DylibCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "dylib", abstract: "dylib commands")
    static let pointer = "not applicable — taptaptap doesn't inject dylibs"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}

struct MediaCommand: UnsupportedIdbCommand {
    static let configuration = CommandConfiguration(commandName: "media", abstract: "Add media to the target")
    static let pointer = "xcrun simctl addmedia <udid> <path>"
    @Argument var rest: [String] = []
    @Option(name: .customLong("udid")) var udid: String?
}
