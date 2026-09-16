import Darwin
import Foundation
import Testing
@testable import TapTapTapCLI

/// F3 (TESTING.md): stale HID broker socket/lock files accumulated in `$TMPDIR/taptaptap-hid-<uid>/`
/// after brokers exited. `pruneStaleEndpoints` sweeps a directory and removes only entries with no
/// live holder -- these tests exercise the liveness discriminator directly (real flocks, real
/// listening sockets) rather than age, since age alone could delete a slow-but-live broker's files.
///
/// Uses its own isolated temp directory rather than the real shared `taptaptap-hid-<uid>` root:
/// `pruneStaleEndpoints` takes an explicit `rootDirectory`, and other suites (HIDBrokerTests,
/// HIDBrokerReliabilityTests) create real sockets/locks in that shared root concurrently -- a
/// sweep of the real root here could race and prune another suite's live-but-momentarily-unlocked
/// fixture.
@Suite("HID Broker Pruning Tests")
struct HIDBrokerPruningTests {
    @Test("A dead (unheld) lock file is pruned; a live (flocked) one survives")
    func pruneDiscriminatesLockLiveness() throws {
        let root = try makeIsolatedRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        // Dead: create the lock file and immediately release it, matching a broker that exited
        // normally (which never unlinks its own lock files -- that's the pre-existing design).
        let deadLockPath = root + "/d.lock"
        let deadDescriptor = try #require(createPrivateLockFile(at: deadLockPath))
        Darwin.close(deadDescriptor)
        #expect(FileManager.default.fileExists(atPath: deadLockPath))

        // Live: hold the flock for the duration of the prune call.
        let liveLockPath = root + "/l.lock"
        let liveDescriptor = try #require(createPrivateLockFile(at: liveLockPath))
        defer { Darwin.close(liveDescriptor) }
        #expect(flock(liveDescriptor, LOCK_EX | LOCK_NB) == 0)

        HIDBroker.pruneStaleEndpoints(rootDirectory: root)

        #expect(!FileManager.default.fileExists(atPath: deadLockPath), "an unheld lock should be pruned")
        #expect(FileManager.default.fileExists(atPath: liveLockPath), "a flocked lock must survive pruning")
    }

    @Test("A dead (unlistened) socket is pruned; a live listener's socket survives")
    func pruneDiscriminatesSocketLiveness() throws {
        let root = try makeIsolatedRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let deadPath = root + "/d.sock"
        let livePath = root + "/l.sock"

        // Dead: bind+listen, then close without unlinking -- the file remains but nothing answers.
        let deadListener = try HIDBroker.makeListener(at: deadPath)
        Darwin.close(deadListener)
        #expect(FileManager.default.fileExists(atPath: deadPath))

        // Live: a real listener stays open for the duration of the prune call.
        let liveListener = try HIDBroker.makeListener(at: livePath)
        defer { Darwin.close(liveListener) }

        HIDBroker.pruneStaleEndpoints(rootDirectory: root)

        #expect(!FileManager.default.fileExists(atPath: deadPath), "an unlistened socket should be pruned")
        #expect(FileManager.default.fileExists(atPath: livePath), "a live listener's socket must survive pruning")
    }

    @Test("excludingIdentity skips a not-yet-live identity's own files even though they're unheld")
    func excludingIdentitySkipsOwnFiles() throws {
        let root = try makeIsolatedRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        // An about-to-be-recreated identity's lock: unheld right now (like a fresh O_CREAT file
        // nobody has flocked yet), but must survive because it's excluded by name.
        let ownLockPath = root + "/own.lock"
        let ownDescriptor = try #require(createPrivateLockFile(at: ownLockPath))
        Darwin.close(ownDescriptor)

        HIDBroker.pruneStaleEndpoints(rootDirectory: root, excludingIdentity: "own")

        #expect(FileManager.default.fileExists(atPath: ownLockPath), "an excluded identity's file must survive even though it's unheld")
    }

    /// A fresh, privately-owned 0700 directory, isolated from the real shared broker root and
    /// from every other test's isolated root.
    private func makeIsolatedRoot() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ttp-prune-\(UUID().uuidString.prefix(8))")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return path
    }

    private func createPrivateLockFile(at path: String) -> Int32? {
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        return descriptor >= 0 ? descriptor : nil
    }
}
