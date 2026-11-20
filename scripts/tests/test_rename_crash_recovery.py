"""Real child-process SIGKILL crash-gate tests for F2 / AM-04 rename recovery.

Compiles the committed production RenameTransactionService and its Foundation/Darwin
dependencies once into a disposable binary, then kills real child processes with
SIGKILL at every prescribed durability and move gate. Fresh child processes classify
and restore from persisted journal state, verifying exact SHA-256 byte identity.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]

PRODUCTION_SOURCES = [
    "AudioMator/Core/FileSystem/FileSystemPathSemantics.swift",
    "AudioMator/Domain/AudioFiles/AudioFileFingerprint.swift",
    "AudioMator/Domain/Rename/RenameEntryIdentity.swift",
    "AudioMator/Domain/Rename/RenameJournalManifest.swift",
    "AudioMator/Domain/Rename/RenameTransactionContract.swift",
    "AudioMator/Infrastructure/FileSystem/FileEntryIdentity.swift",
    "AudioMator/Infrastructure/FileSystem/RenameFileSystem.swift",
    "AudioMator/Infrastructure/FileSystem/RenameJournalStore.swift",
    "AudioMator/Infrastructure/FileSystem/RenameTransactionService.swift",
]

HARNESS_MAIN_SWIFT = r"""
import Darwin
import Foundation

private enum GateMode: String {
    case crashAfterPrepare = "crash-after-prepare"
    case crashAfterFirstStage = "crash-after-first-stage"
    case crashAfterAllStaged = "crash-after-all-staged"
    case crashAfterPartialFinalize = "crash-after-partial-finalize"
    case crashAfterAllFinalizedBeforeCommit = "crash-after-all-finalized-before-commit"
    case crashAfterCommittedMarker = "crash-after-committed-marker"
    case crashDuringRestore = "crash-during-restore"
    case classify = "classify"
    case restore = "restore"
}

private final class GateJournalStore: RenameJournalStoring, @unchecked Sendable {
    let base: LocalRenameJournalStore
    let killAfterPrepare: Bool
    let killAfterCommitted: Bool

    init(base: LocalRenameJournalStore, killAfterPrepare: Bool = false, killAfterCommitted: Bool = false) {
        self.base = base
        self.killAfterPrepare = killAfterPrepare
        self.killAfterCommitted = killAfterCommitted
    }

    var directoryURL: URL { base.directoryURL }
    func ensureDirectory() throws { try base.ensureDirectory() }
    func loadManifests() -> RenameJournalLoadResult { base.loadManifests() }
    func tryAcquireLock() throws -> RenameJournalLock? { try base.tryAcquireLock() }
    func directoryBarrierSupport() -> RenameDirectoryBarrierSupport { base.directoryBarrierSupport() }

    func writePrepared(_ manifest: RenameJournalManifest) throws {
        try base.writePrepared(manifest)
        if killAfterPrepare {
            kill(getpid(), SIGKILL)
        }
    }

    func markCommitted(_ manifest: RenameJournalManifest) throws {
        try base.markCommitted(manifest)
        if killAfterCommitted {
            kill(getpid(), SIGKILL)
        }
    }

    func removeManifest(operationID: UUID) throws {
        try base.removeManifest(operationID: operationID)
    }
}

private final class GateRenameFileSystem: RenameFileSystem, @unchecked Sendable {
    let base = LocalRenameFileSystem()
    let killAfterMoveCount: Int?
    private let lock = NSLock()
    private var moveCount = 0

    init(killAfterMoveCount: Int? = nil) {
        self.killAfterMoveCount = killAfterMoveCount
    }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func fingerprint(at url: URL) throws -> AudioFileFingerprint { try base.fingerprint(at: url) }
    func entryIdentity(at url: URL) throws -> RenameEntryIdentity { try base.entryIdentity(at: url) }
    func entryIdentityIfPresent(at url: URL) throws -> RenameEntryIdentity? {
        try base.entryIdentityIfPresent(at: url)
    }
    func linkTarget(at url: URL) -> String? { base.linkTarget(at: url) }
    func volumeIdentifier(forDirectoryAt url: URL) -> String? { base.volumeIdentifier(forDirectoryAt: url) }
    func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool {
        try base.volumeSupportsExclusiveRename(forDirectoryAt: url)
    }
    func openDirectory(at url: URL) throws -> RenameDirectoryHandle { try base.openDirectory(at: url) }
    func directoryIdentity(_ handle: RenameDirectoryHandle) throws -> RenameDirectoryIdentity {
        try base.directoryIdentity(handle)
    }
    func authorizedPathStillIdentifiesDirectory(_ handle: RenameDirectoryHandle) -> Bool {
        base.authorizedPathStillIdentifiesDirectory(handle)
    }
    func entryIdentity(named name: String, in handle: RenameDirectoryHandle) throws -> RenameEntryIdentity? {
        try base.entryIdentity(named: name, in: handle)
    }
    func actualEntryName(inDirectoryAt url: URL, matching name: String) throws -> String? {
        try base.actualEntryName(inDirectoryAt: url, matching: name)
    }
    func exclusiveMove(named sourceName: String, to destinationName: String, in handle: RenameDirectoryHandle) throws {
        try base.exclusiveMove(named: sourceName, to: destinationName, in: handle)
        let current = lock.withLock { () -> Int in
            moveCount += 1
            return moveCount
        }
        if let killAfterMoveCount, current == killAfterMoveCount {
            kill(getpid(), SIGKILL)
        }
    }
    func syncDirectory(_ handle: RenameDirectoryHandle) throws {
        try base.syncDirectory(handle)
    }
}

private func makePreparedTransaction(audioDir: URL) throws -> PreparedRenameTransaction {
    let operationID = UUID()
    let pairs = [
        ("alpha.wav", "alpha-new.wav"),
        ("beta.wav", "beta-new.wav")
    ]
    let entries: [PreparedRenameEntry] = try pairs.enumerated().map { index, pair in
        let original = audioDir.appendingPathComponent(pair.0)
        let intended = audioDir.appendingPathComponent(pair.1)
        let temporary = RenameStagingName.url(for: original, operationID: operationID, index: index)
        return PreparedRenameEntry(
            index: index,
            fileID: UUID(),
            originalURL: original,
            temporaryURL: temporary,
            intendedURL: intended,
            expectedSourceFingerprint: try AudioFileFingerprint.capture(at: original)
        )
    }
    return PreparedRenameTransaction(operationID: operationID, entries: entries)
}

@main
struct RenameCrashHarness {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let mode = GateMode(rawValue: args[1]) else {
            fputs("Usage: rename-crash-harness <mode> <audio-dir> <journal-dir>\n", stderr)
            exit(2)
        }
        let audioDir = URL(fileURLWithPath: args[2], isDirectory: true)
        let journalDir = URL(fileURLWithPath: args[3], isDirectory: true)
        let baseJournal = LocalRenameJournalStore(directoryURL: journalDir)

        switch mode {
        case .crashAfterPrepare:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(),
                journal: GateJournalStore(base: baseJournal, killAfterPrepare: true)
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashAfterFirstStage:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(killAfterMoveCount: 1),
                journal: baseJournal
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashAfterAllStaged:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(killAfterMoveCount: 2),
                journal: baseJournal
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashAfterPartialFinalize:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(killAfterMoveCount: 3),
                journal: baseJournal
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashAfterAllFinalizedBeforeCommit:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(killAfterMoveCount: 4),
                journal: baseJournal
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashAfterCommittedMarker:
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(),
                journal: GateJournalStore(base: baseJournal, killAfterCommitted: true)
            )
            _ = service.execute(try makePreparedTransaction(audioDir: audioDir))
            exit(3)

        case .crashDuringRestore:
            let load = baseJournal.loadManifests()
            guard let manifest = load.manifests.first else { exit(4) }
            let service = RenameTransactionService(
                fileSystem: GateRenameFileSystem(killAfterMoveCount: 1),
                journal: baseJournal
            )
            _ = service.restoreOriginals(manifest)
            exit(3)

        case .classify:
            let load = baseJournal.loadManifests()
            let service = RenameTransactionService(
                fileSystem: LocalRenameFileSystem(),
                journal: baseJournal
            )
            let classifications = service.classify(load.manifests)
            for item in classifications {
                print("STATUS:\(item.status)")
            }
            print("ISSUES:\(load.issues.count)")
            print("MANIFESTS:\(load.manifests.count)")

        case .restore:
            let load = baseJournal.loadManifests()
            guard let manifest = load.manifests.first else {
                print("RESTORE:none")
                return
            }
            let service = RenameTransactionService(
                fileSystem: LocalRenameFileSystem(),
                journal: baseJournal
            )
            switch service.restoreOriginals(manifest) {
            case .restored:
                print("RESTORE:restored")
            case .rejected(let rejection):
                print("RESTORE:rejected:\(rejection)")
            case .busy:
                print("RESTORE:busy")
            case .unresolved:
                print("RESTORE:unresolved")
            }
        }
    }
}
"""


class RenameCrashRecoveryProcessTests(unittest.TestCase):
    """Real child-process SIGKILL crash-gate verification against production sources."""

    _build_dir: tempfile.TemporaryDirectory[str]
    _harness_bin: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls._build_dir = tempfile.TemporaryDirectory(prefix="am-rename-crash-harness-")
        build_root = Path(cls._build_dir.name)
        main_swift = build_root / "main.swift"
        main_swift.write_text(HARNESS_MAIN_SWIFT, encoding="utf-8")
        cls._harness_bin = build_root / "rename-crash-harness"
        module_cache = build_root / "module-cache"
        module_cache.mkdir()

        sdk_path = subprocess.check_output(
            ["xcrun", "--show-sdk-path"],
            text=True,
        ).strip()

        cmd = [
            "xcrun",
            "swiftc",
            "-sdk",
            sdk_path,
            "-module-cache-path",
            str(module_cache),
            "-parse-as-library",
            "-o",
            str(cls._harness_bin),
            *[str(REPO_ROOT / rel) for rel in PRODUCTION_SOURCES],
            str(main_swift),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to build rename crash harness:\n{result.stderr}")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._build_dir.cleanup()

    def _make_workspace(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path, dict[str, str]]:
        tmp = tempfile.TemporaryDirectory(prefix="am-rename-crash-case-")
        root = Path(tmp.name).resolve()
        audio_dir = root / "audio"
        journal_dir = root / "journal"
        audio_dir.mkdir()
        journal_dir.mkdir()
        payloads = {
            "alpha.wav": b"RIFF-alpha-payload-0123456789",
            "beta.wav": b"RIFF-beta-payload-abcdefghij",
        }
        hashes: dict[str, str] = {}
        for name, data in payloads.items():
            (audio_dir / name).write_bytes(data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        return tmp, audio_dir, journal_dir, hashes

    def _run(self, mode: str, audio_dir: Path, journal_dir: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self._harness_bin), mode, str(audio_dir), str(journal_dir)],
            capture_output=True,
            text=True,
        )

    def _assert_originals_intact(self, audio_dir: Path, expected_hashes: dict[str, str]) -> None:
        visible = sorted(p.name for p in audio_dir.iterdir())
        self.assertEqual(visible, sorted(expected_hashes.keys()))
        for name, digest in expected_hashes.items():
            actual = hashlib.sha256((audio_dir / name).read_bytes()).hexdigest()
            self.assertEqual(actual, digest)

    def test_prepared_crash_gates_classify_and_restore_to_byte_identical_originals(self) -> None:
        gates = [
            ("crash-after-prepare", "preparedNoFilesMoved"),
            ("crash-after-first-stage", "preparedNeedsRestore"),
            ("crash-after-all-staged", "preparedNeedsRestore"),
            ("crash-after-partial-finalize", "preparedNeedsRestore"),
            ("crash-after-all-finalized-before-commit", "preparedAllAtIntended"),
        ]
        for gate, expected_status in gates:
            with self.subTest(gate=gate):
                tmp, audio_dir, journal_dir, hashes = self._make_workspace()
                try:
                    killed = self._run(gate, audio_dir, journal_dir)
                    self.assertEqual(killed.returncode, -signal.SIGKILL, f"Expected SIGKILL for {gate}")

                    classified = self._run("classify", audio_dir, journal_dir)
                    self.assertEqual(classified.returncode, 0, classified.stderr)
                    self.assertIn(f"STATUS:{expected_status}", classified.stdout)
                    self.assertIn("MANIFESTS:1", classified.stdout)

                    restored = self._run("restore", audio_dir, journal_dir)
                    self.assertEqual(restored.returncode, 0, restored.stderr)
                    self.assertIn("RESTORE:restored", restored.stdout)
                    self._assert_originals_intact(audio_dir, hashes)

                    after_classify = self._run("classify", audio_dir, journal_dir)
                    self.assertEqual(after_classify.returncode, 0)
                    self.assertIn("MANIFESTS:0", after_classify.stdout)
                finally:
                    tmp.cleanup()

    def test_crash_after_committed_marker_preserves_new_names_and_refuses_restore(self) -> None:
        tmp, audio_dir, journal_dir, hashes = self._make_workspace()
        try:
            killed = self._run("crash-after-committed-marker", audio_dir, journal_dir)
            self.assertEqual(killed.returncode, -signal.SIGKILL)

            classified = self._run("classify", audio_dir, journal_dir)
            self.assertEqual(classified.returncode, 0, classified.stderr)
            self.assertIn("STATUS:committedConfirmed", classified.stdout)

            restored = self._run("restore", audio_dir, journal_dir)
            self.assertEqual(restored.returncode, 0, restored.stderr)
            self.assertIn("RESTORE:rejected:committedRecordFinal", restored.stdout)

            # Final intended names stay intact with identical bytes.
            self.assertEqual(
                sorted(p.name for p in audio_dir.iterdir()),
                ["alpha-new.wav", "beta-new.wav"],
            )
            self.assertEqual(
                hashlib.sha256((audio_dir / "alpha-new.wav").read_bytes()).hexdigest(),
                hashes["alpha.wav"],
            )
            self.assertEqual(
                hashlib.sha256((audio_dir / "beta-new.wav").read_bytes()).hexdigest(),
                hashes["beta.wav"],
            )
        finally:
            tmp.cleanup()

    def test_crash_during_restore_remains_resumable_and_idempotent(self) -> None:
        tmp, audio_dir, journal_dir, hashes = self._make_workspace()
        try:
            killed_forward = self._run("crash-after-all-finalized-before-commit", audio_dir, journal_dir)
            self.assertEqual(killed_forward.returncode, -signal.SIGKILL)

            killed_restore = self._run("crash-during-restore", audio_dir, journal_dir)
            self.assertEqual(killed_restore.returncode, -signal.SIGKILL)

            classified = self._run("classify", audio_dir, journal_dir)
            self.assertEqual(classified.returncode, 0, classified.stderr)
            self.assertIn("STATUS:preparedNeedsRestore", classified.stdout)

            resumed = self._run("restore", audio_dir, journal_dir)
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            self.assertIn("RESTORE:restored", resumed.stdout)
            self._assert_originals_intact(audio_dir, hashes)
        finally:
            tmp.cleanup()


if __name__ == "__main__":
    unittest.main()
