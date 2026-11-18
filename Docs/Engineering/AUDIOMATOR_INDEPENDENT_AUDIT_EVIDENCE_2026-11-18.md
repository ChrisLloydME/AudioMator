# Independent audit supporting evidence

**Dated evidence · 2026-11-18 · main at `b37de1133ab7b36fa5e0a3073bec18e3384cfd70`**

This is the evidence companion to the [independent audit](AUDIOMATOR_INDEPENDENT_AUDIT_2026-11-18.md). Commands and canaries target disposable copies of the audited source and repository audio fixtures. Retained output below is selected evidence from the audit, with machine-specific paths removed. The original full logs, result bundle, compiled programs, and generated source amalgamations were temporary. Command examples reconstructed for replay are labeled as such.

## Baseline outputs

The audit ran the original SwiftPM and app suites, unsigned Release build and artifact check, and link checker as separate steps. The separate reproduction test failed after the baseline passed. Host and exact build flags appear in the audit.

```text
# branch.oid b37de1133ab7b36fa5e0a3073bec18e3384cfd70
# branch.head main
# branch.upstream origin/main
# branch.ab +0 -0
1 .M N... 100644 100644 100644 f6c895a9c3fb2ec6968b0471c064fe55b22adcdc f6c895a9c3fb2ec6968b0471c064fe55b22adcdc AudioMator/Localizable.xcstrings
Xcode 27.2 (27B52), macOS 27.2.1 (26B131), arm64, Apple Swift 6.4.2
13 policy tests passed
62 Foundation XCTest cases passed
630 serial app-hosted XCTest cases passed
Resolved TagLibAudioMetadata 0.8.1 at b8ed5475761cb50bacdd7dcd4f6e2f61142303d0
** BUILD SUCCEEDED **
Validated Contents/MacOS/AudioMator: minOS 15.0, 15.0
Validated Contents/Frameworks/TagLibAudioMetadataTagLib.framework/Versions/A/TagLibAudioMetadataTagLib: minOS 13.0, 13.0
Validated bundle minimum 15.0 and 2 Mach-O files.
lipo: x86_64 arm64 for both binaries
check-doc-links: 49 Markdown file(s) checked, no problems found
```

```json
{
  "core-gate": {
    "accepted": true,
    "expected": 62,
    "executed": 62,
    "missing": [],
    "unexpected": []
  },
  "app-gate": {
    "accepted": true,
    "reasons": [],
    "expected": 630,
    "executed": 630,
    "missing": [],
    "unexpected": []
  },
  "repository-integrity": {
    "status_matches": true,
    "index_matches": true,
    "content_and_modes_match": true,
    "paths": 405,
    "changed_paths": [],
    "dirty_diff_sha256": "37345ae919718ee62b53c9eafac27ee1622c4bc818d32ec4bcff242eb544efad",
    "localization_sha256": "395879551c1aa61937bb60b0eac6f1efb0f8bac89d89d5bfa9e349484620737f"
  },
  "app-xcresult-summary": {
    "result": "Passed",
    "totalTestCount": 630,
    "passedTests": 630,
    "failedTests": 0,
    "skippedTests": 0,
    "expectedFailures": 0
  }
}
```

The catalog diff removed only the empty `"Current"` and `"Imported"` entries. The following patch replays the exact catalog contents in a disposable copy of the audited revision. Its final blank context line is omitted, so the patch text itself has a different digest from the original dirty diff.

```diff
diff --git a/AudioMator/Localizable.xcstrings b/AudioMator/Localizable.xcstrings
index f6c895a9..fec79003 100644
--- a/AudioMator/Localizable.xcstrings
+++ b/AudioMator/Localizable.xcstrings
@@ -3306,9 +3306,6 @@
           }
         }
       }
-    },
-    "Current" : {
-
     },
     "Current list" : {
       "comment" : "Short UI label. Used around: AudioMator/Features/Main/Views/TrackRenumberSheet.swift:91.",
@@ -5342,8 +5339,5 @@
           }
         }
       }
-    },
-    "Imported" : {
-
     },
     "Importing Metadata" : {
```

## FLAC removal

Copy the following exact test source to `AudioMatorTests/AuditExchangeReproductions.swift` in an isolated baseline copy. Run the audit's serial Debug command with `-only-testing:AudioMatorTests/AuditExchangeReproductions` and a fresh result path. This was a single-test diagnostic, separate from the 630-case baseline. It exercises the planned intent conversion and actual adapter, with no directory authorization panel.

```text
Independent readback track=0 total=0
XCTAssertEqual failed: ("0") is not equal to ("12") - A single-field removal must keep the existing total
Executed 1 test, with 1 failure (0 unexpected)
```

```swift
import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class AuditExchangeReproductions: XCTestCase {
    @MainActor
    func testCSVTrackRemovalPreservesUntargetedTotal() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource: "testAudioFile", withExtension: "flac", subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile", withExtension: "flac"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("synthetic.flac")
        try FileManager.default.copyItem(at: fixture, to: copy)
        let id = UUID()
        let original = try await pipeline.loadAudioFile(at: copy, id: id)
        var seed = SingleFileEditModel(from: original)
        seed.setTrackNumberText("3/12")
        _ = try pipeline.writeMetadata(MetadataEditPayload(seed, comparedTo: original), to: copy, expectedVersion: original.metadataFileVersion)
        let seeded = try await pipeline.loadAudioFile(at: copy, id: id)
        XCTAssertEqual(seeded.track, 3)
        XCTAssertEqual(seeded.trackTotal, 12)

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}",
            sourceText: "# AudioMator-Metadata-Profile: 2\n<remove>",
            firstRowIsHeader: false,
            targetFiles: [seeded],
            clearBlankImportedValues: false
        )
        let row = try XCTUnwrap(plan.rows.first)
        XCTAssertEqual(row.changes.filter(\.willWrite).map(\.field), [.trackNumber])
        let entry = try XCTUnwrap(row.writeEntry)
        var edit = SingleFileEditModel(from: seeded)
        for field in MetadataExchangeField.allCases {
            guard let value = entry.values[field] else { continue }
            field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: entry.preservingNumberPairComponents)
        }
        _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: seeded), to: copy, expectedVersion: seeded.metadataFileVersion)
        let persisted = try await pipeline.loadAudioFile(at: copy, id: id)
        print("Independent readback track=\(persisted.track) total=\(persisted.trackTotal)")
        XCTAssertEqual(persisted.track, 0)
        XCTAssertEqual(persisted.trackTotal, 12, "A single-field removal must keep the existing total")
    }
}
```

## CSV parser mutation

In a disposable baseline copy, inject a branch in the CSV parser's delimiter path that skips adding the first field if the row is empty and the field buffer has no content. Keep the existing tests byte-identical. Compile the original and modified [CSV source](../../AudioMator/Domain/MetadataExchange/MetadataExchangeCSV.swift) separately, and apply the same independent literal canary `,New Title`. Run the same Foundation test command on the modified copy. The audit observed the following.

```text
Original: [["", "New Title"]]
Mutant:   [["New Title"]]
Mutant fast lane: Executed 62 tests, with 0 failures (0 unexpected)
```

The app-hosted test that asserts both empty fields of `,` was not run on the mutation. Its expectation would detect the mutation. This is a fast-lane result.

## Rename interruption

The harness compiled the production transaction declarations and functions extracted verbatim from lines 14–64 and 249–529 of [AudioViewModel+FileRename.swift](../../AudioMator/Features/Main/ViewModels/AudioViewModel+FileRename.swift), with an `import Foundation` prefix, plus the production fingerprint and path semantics. Normal mode moved the canary to `b.wav`. Interruption mode terminated its own child process after the successful stage move. Parent inspection found only the hidden file and verified the payload.

```text
control: b.wav contains original bytes
interruption: child return code -9; a.wav absent; b.wav absent; .audiomator-rename-<UUID>.wav byte-identical
```

The runner below is the retained Swift entry point. Compile it as `main.swift` in a disposable directory alongside the extracted functions and helpers using `xcrun swiftc -module-cache-path <disposable-cache> … -o <disposable-executable>`. Invoke the executable once with an empty disposable directory, then with a different empty directory and an extra mode argument. Inspect the second directory including hidden entries. The helper writes to its argument directory; use a fresh temporary path for each invocation.

```swift
import Foundation
import Darwin

private struct CrashAfterStage: FileRenameFileSystem {
    nonisolated private let local = LocalFileRenameFileSystem()

    nonisolated func fileExists(at url: URL) -> Bool {
        local.fileExists(at: url)
    }
    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        try local.fingerprint(at: url)
    }
    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try local.moveItem(at: sourceURL, to: destinationURL)
        if destinationURL.lastPathComponent.hasPrefix(".audiomator-rename-") {
            kill(getpid(), SIGKILL)
        }
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = root.appendingPathComponent("a.wav")
let destination = root.appendingPathComponent("b.wav")
let fileManager = FileManager.default
try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
try Data("audiomator crash recovery canary".utf8).write(to: source)
let operation = try FileRenameOperation(
    id: UUID(),
    sourceURL: source,
    destinationURL: destination,
    expectedFileFingerprint: AudioFileFingerprint.capture(at: source)
)
if CommandLine.arguments.count > 2 {
    _ = executeFileRenameTransaction([operation], fileSystem: CrashAfterStage())
    preconditionFailure("did not terminate")
}
guard case .success = executeFileRenameTransaction([operation]) else {
    preconditionFailure("normal rename did not complete")
}
precondition(!fileManager.fileExists(atPath: source.path))
let payload = try String(contentsOf: destination, encoding: .utf8)
precondition(payload == "audiomator crash recovery canary")
print("completed control: b.wav contains original bytes")
```

## Directory monitor

Compile the following entry point as `main.swift` with [DirectoryMonitor.swift](../../AudioMator/Infrastructure/FileSystem/DirectoryMonitor.swift) and [FileSystemPathSemantics.swift](../../AudioMator/Core/FileSystem/FileSystemPathSemantics.swift). It creates synthetic temporary paths and positive controls. Local APFS evidence was that directory entries triggered the current descriptor, in-place file writes triggered neither directory descriptor, the original descriptor followed the moved directory, and a newly opened descriptor detected new entries at the replaced path.

```swift
import Darwin
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let watched = root.appendingPathComponent("subdirectory", isDirectory: true)
let moved = root.appendingPathComponent("former", isDirectory: true)
let file = watched.appendingPathComponent("synthetic.wav")
let files = FileManager.default
try files.createDirectory(at: watched, withIntermediateDirectories: true)
try Data("before".utf8).write(to: file)
let events = DispatchSemaphore(value: 0)
let rootedEvents = DispatchSemaphore(value: 0)
func received(_ events: DispatchSemaphore, within timeout: DispatchTimeInterval = .milliseconds(700)) -> Bool {
    events.wait(timeout: .now() + timeout) == .success
}

let watcher = DirectoryMonitor(url: watched) { events.signal() }!
let rootWatcher = DirectoryMonitor(url: root) { rootedEvents.signal() }!
watcher.start()
rootWatcher.start()
Thread.sleep(forTimeInterval: 0.1)
let write = try FileHandle(forWritingTo: file)
try write.seek(toOffset: 0)
try write.write(contentsOf: Data("after!".utf8))
try write.close()
let inplaceEvent = received(events)
let inplaceRootEvent = received(rootedEvents, within: .milliseconds(50))
print("Existing file in-place write: subdirectory event \(inplaceEvent), root event \(inplaceRootEvent)")
precondition(!inplaceEvent && !inplaceRootEvent)
precondition(try! String(contentsOf: file, encoding: .utf8) == "after!")

try Data("before".utf8).write(to: watched.appendingPathComponent("entry-created.wav"))
let creationEvent = received(events)
print("Directory entry creation control: subdirectory event \(creationEvent)")
precondition(creationEvent)

let oldKey = FileSystemPathSemantics.key(for: watched)
try files.moveItem(at: watched, to: moved)
try files.createDirectory(at: watched, withIntermediateDirectories: false)
let renameEvent = received(events)
let renameRootEvent = received(rootedEvents)
precondition(renameEvent && renameRootEvent)
precondition(oldKey == FileSystemPathSemantics.key(for: watched))
Thread.sleep(forTimeInterval: 0.1)
while received(events, within: .milliseconds(20)) {}
while received(rootedEvents, within: .milliseconds(20)) {}
let replacementEvents = DispatchSemaphore(value: 0)
let replacement = DirectoryMonitor(url: watched) { replacementEvents.signal() }!
replacement.start()
Thread.sleep(forTimeInterval: 0.1)
try Data("replacement".utf8).write(to: watched.appendingPathComponent("new-entry.wav"))
let retainedEvent = received(events)
let retainedRootEvent = received(rootedEvents, within: .milliseconds(50))
let replacementEvent = received(replacementEvents)
print("New directory at same key: retained subdirectory event \(retainedEvent), root event \(retainedRootEvent), fresh subdirectory event \(replacementEvent)")
precondition(!retainedEvent && !retainedRootEvent && replacementEvent)

try Data("elsewhere".utf8).write(to: moved.appendingPathComponent("former-entry.wav"))
let movedEvent = received(events)
print("Retained watcher follows moved directory: \(movedEvent)")
precondition(movedEvent)
watcher.stop()
rootWatcher.stop()
replacement.stop()
```

## Quick Import path work

The optimized harness isolates the existing-key and in-flight scope key passes. Compile this entry point with `xcrun swiftc -O` and [FileSystemPathSemantics.swift](../../AudioMator/Core/FileSystem/FileSystemPathSemantics.swift) and pass `480` or `960` as the count. The single-run recorded results were 17,040 key operations, 0.56 s cumulative and 76.6 ms longest callback at 480, and 67,680 operations, 2.28 s cumulative and 152.8 ms longest callback at 960. The audit did not measure tag decoding, security-scoped access calls, or rendering.

```swift
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let count = Int(CommandLine.arguments[2])!
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let urls = try (0..<count).map { index in
    let file = root.appendingPathComponent("file-\(index).wav")
    try Data().write(to: file)
    return file
}
let clock = ContinuousClock()
let start = clock.now
var keyCalls = 0
var batchTimes: [Duration] = []
for completion in stride(from: 48, through: count, by: 48) {
    let initial = clock.now
    let existing = urls.prefix(completion - 48)
    var mergeByKey: [String: Int] = [:]
    for (index, url) in existing.enumerated() {
        let key = FileSystemPathSemantics.key(for: url)
        keyCalls += 1
        mergeByKey[key] = index
    }
    let all = Array(urls.prefix(completion)) + urls
    var fileURLs: [String: URL] = [:]
    var directoryURLs: [String: URL] = [:]
    for url in all {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        fileURLs[FileSystemPathSemantics.key(for: standardized)] = standardized
        directoryURLs[FileSystemPathSemantics.key(for: parent)] = parent
        keyCalls += 2
    }
    precondition(mergeByKey.count == existing.count && fileURLs.count == count && directoryURLs.count == 1)
    batchTimes.append(initial.duration(to: .now))
}
print("\(count) files, \(batchTimes.count) batches, \(keyCalls) calls, cumulative \(start.duration(to: .now)), longest batch \(batchTimes.max()!)")
```

## Provider probes

Retained output from the three standalone runs follows. They used fake provider responses and synthetic file metadata.

```text
closed files=0, provider requests=["Synthetic One", "Synthetic Two"], write-ready matches after close=2
same-client decode failures=2, real requests=1, fresh cache title=Synthetic Recording, total requests=2
first country=us, selected country=jp, second detail country=us, detail requested=["us"]
```

Save the following runner and three sources together in a disposable directory. Pass the isolated checkout root explicitly to the runner. The command paths below are adapted for portability. All inputs are synthetic.

```bash
#!/usr/bin/env bash
set -euo pipefail
fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="${1:?Pass the disposable AudioMator checkout root}"
cd "$source_root"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swiftc=(xcrun swiftc -swift-version 5 -strict-concurrency=complete -default-isolation MainActor -module-cache-path "$fixture/ModuleCache")
common=(
    AudioMator/Infrastructure/OnlineMetadata/OnlineMetadataSelectionCore.swift
    AudioMator/Infrastructure/iTunes/iTunesProviderCore.swift
    AudioMator/Core/Audio/AudioTagNumberPair.swift
    AudioMator/Core/Audio/AudioTagNumberText.swift
    AudioMator/Core/Audio/AudioNumericConversion.swift
    AudioMator/Core/Text/FuzzyStringSimilarity.swift
)
"${swiftc[@]}" AudioMator/Features/LRCLIBLyricsBrowser/ViewModels/LRCLIBLyricsBrowserStore.swift \
    AudioMator/Infrastructure/LRCLIB/*.swift AudioMator/Core/Audio/AudioNumericConversion.swift \
    "$fixture/ServicesProbe.swift" -o "$fixture/lyrics-probe"
"$fixture/lyrics-probe"
musicbrainz=()
for source_file in AudioMator/Infrastructure/MusicBrainz/*.swift; do
    [[ "$source_file" != */MusicBrainzFilenameFallback.swift ]] || continue
    musicbrainz+=("$source_file")
done
"${swiftc[@]}" "${common[@]}" "${musicbrainz[@]}" AudioMator/Core/Network/NetworkServiceDisclosure.swift \
    "$fixture/MusicBrainzProbe.swift" -o "$fixture/musicbrainz-probe"
"$fixture/musicbrainz-probe"
"${swiftc[@]}" "${common[@]}" AudioMator/Features/iTunesBrowser/ViewModels/iTunesBrowserStore.swift \
    AudioMator/Infrastructure/iTunes/iTunesClient.swift AudioMator/Core/Concurrency/AsyncOperationDeadline.swift \
    "$fixture/iTunesProbe.swift" -o "$fixture/itunes-probe"
"$fixture/itunes-probe"
```

### ServicesProbe.swift

```swift
import Foundation

nonisolated struct AudioFile {
    typealias ID = UUID
    let id = UUID()
    let url: URL
    let title: String
    let artist = "Synthetic Artist"
    let album = "Synthetic Album"
    let duration = 100.0
}

nonisolated enum MusicBrainzFilenameFallbackResolver {
    struct Result {
        let title = ""
        let artist = ""
        let album = ""
        let durationMilliseconds: Int? = nil
    }

    static func makeSearchInput(for file: AudioFile) -> Result { Result() }
}

actor BlockedLyricsClient: LRCLIBLyricsSearching {
    private var titles: [String] = []
    private var onFirstRequest: CheckedContinuation<Void, Never>?
    private var resumeFirst: CheckedContinuation<Void, Never>?

    func search(matching query: LRCLIBSearchQuery, limit: Int) async throws -> [LRCLIBLyricsCandidate] {
        titles.append(query.trackName)
        if titles.count == 1 {
            await withCheckedContinuation { continuation in
                resumeFirst = continuation
                onFirstRequest?.resume()
                onFirstRequest = nil
            }
        }
        return [.init(id: titles.count, name: nil, trackName: query.trackName, artistName: query.artistName,
                      albumName: query.albumName, duration: 100, instrumental: false,
                      plainLyrics: nil, syncedLyrics: "[00:01.00]Synthetic")]
    }

    func waitUntilBlocked() async {
        if resumeFirst == nil { await withCheckedContinuation { onFirstRequest = $0 } }
    }

    func releaseFirst() {
        resumeFirst?.resume()
        resumeFirst = nil
    }

    func requests() -> [String] { titles }
}

@main
struct Runner {
    @MainActor static func main() async {
        let client = BlockedLyricsClient()
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [
            AudioFile(url: URL(fileURLWithPath: "/tmp/synthetic-one.mp3"), title: "Synthetic One"),
            AudioFile(url: URL(fileURLWithPath: "/tmp/synthetic-two.mp3"), title: "Synthetic Two")
        ])
        let task = Task { await store.autoSyncedLyricsMatchesForAllFiles { _, _, _ in } }
        await client.waitUntilBlocked()
        store.closeWindowSession()
        guard !store.hasFiles else { fatalError("Session did not close") }
        await client.releaseFirst()
        let matches = await task.value
        let requests = await client.requests()
        print("closed files=\(store.fileInputs.count), provider requests=\(requests), write-ready matches after close=\(matches.count)")
        guard requests.count == 2, matches.count == 2 else { fatalError("Expected reproduction missing") }
    }
}

```

### MusicBrainzProbe.swift

```swift
import Foundation

nonisolated final class ScriptedProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var expectedBodies: [String] = []
    nonisolated(unsafe) private static var requests = 0

    static func schedule(_ bodies: [String]) {
        lock.withLock {
            expectedBodies = bodies
            requests = 0
        }
    }

    static func observedCount() -> Int { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.lock.withLock {
            Self.requests += 1
            return Self.expectedBodies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct Runner {
    @MainActor static func main() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: settings)
        let cache = MusicBrainzResponseCache()
        let limiter = MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
        let client = MusicBrainzClient(session: session, rateLimiter: limiter, responseCache: cache, retryPolicy: .disabled)
        let valid = #"{"id":"11111111-1111-1111-1111-111111111111","title":"Synthetic Recording"}"#
        ScriptedProtocol.schedule(["this is not JSON", valid])
        var failures = 0
        for _ in 0..<2 {
            do { _ = try await client.recordingDetail(id: "11111111-1111-1111-1111-111111111111") }
            catch MusicBrainzClientError.decodingFailed { failures += 1 }
        }
        let requestsBeforeControl = ScriptedProtocol.observedCount()
        let freshClient = MusicBrainzClient(session: session, rateLimiter: limiter, retryPolicy: .disabled)
        let recovered = try await freshClient.recordingDetail(id: "11111111-1111-1111-1111-111111111111")
        print("same-client decode failures=\(failures), real requests=\(requestsBeforeControl), fresh cache title=\(recovered.title), total requests=\(ScriptedProtocol.observedCount())")
        guard failures == 2, requestsBeforeControl == 1, ScriptedProtocol.observedCount() == 2 else {
            fatalError("Expected reproduction missing")
        }

        let query = MusicBrainzSearchQuery(mode: .track, title: "Synthetic Title")
        ScriptedProtocol.schedule([#"{"recordings":[{"id":"synthetic","title":"Synthetic Title","score":"100"}]}"#])
        do {
            _ = try await client.searchRecordings(matching: query, limit: 1)
            fatalError("Unexpectedly decoded string score")
        } catch MusicBrainzClientError.decodingFailed(let detail) {
            print("string score decode failed: \(detail)")
        }
        ScriptedProtocol.schedule([#"{"recordings":[{"id":"synthetic","title":"Synthetic Title","score":100}]}"#])
        let result = try await freshClient.searchRecordings(matching: query, limit: 1)
        print("integer control score=\(result.first?.score ?? -1)")
        guard result.first?.score == 100 else { fatalError("Expected integer control") }
    }
}

```

### iTunesProbe.swift

```swift
import Foundation

nonisolated enum ContentAdvisory {
    case explicit
    static func fromiTunesExplicitness(_ value: String) -> ContentAdvisory? { value == "explicit" ? .explicit : nil }
}

nonisolated struct AudioFile {
    let id = UUID()
    let trackTotal = 0
    let duration = 0.0
    let barcode = ""
    let itunesAlbumID = ""
    let itunesArtistID = ""
    let itunesCatalogID = ""
}

nonisolated enum MusicBrainzFilenameFallbackResolver {
    struct Result {
        let displayTitle = ""
        let title = ""
        let artist = ""
        let albumArtist = ""
        let album = ""
        let trackNumber = ""
        let discNumber = ""
        let releaseDate = ""
    }
    static func makeSearchInput(for file: AudioFile) -> Result { Result() }
}

actor Catalog: iTunesBrowserClient {
    private var countries: [String] = []
    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        .albums([Self.result(country: query.country)])
    }
    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        countries.append(country)
        return iTunesAlbumDetail(album: Self.result(country: country), tracks: [], selectionMatchPreview: nil)
    }
    func requestedCountries() -> [String] { countries }

    nonisolated static func result(country: String) -> iTunesAlbumResult {
        iTunesAlbumResult(collectionID: 77, artistID: nil, collectionArtistID: nil, collectionName: "Synthetic \(country)",
                         artistName: "", collectionArtistName: "", trackCount: 10, releaseDate: "", primaryGenreName: "",
                         country: country, copyright: "", contentAdvisoryRating: "", collectionExplicitness: "",
                         collectionViewURL: nil, artistViewURL: nil, selectionMatchPreview: nil, selectionMatchScore: nil)
    }
}

@main
struct Runner {
    @MainActor static func main() async throws {
        let client = Catalog()
        let store = iTunesBrowserStore(client: client)
        let first = try await store.albumDetail(for: Catalog.result(country: "us"))
        store.storefront = .jp
        let other = try await store.albumDetail(for: Catalog.result(country: "jp"))
        let requested = await client.requestedCountries()
        print("first country=\(first.album.country), selected country=\(store.storefront.countryCode), second detail country=\(other.album.country), detail requested=\(requested)")
        guard first.album.country == "us", store.storefront == .jp, other.album.country == "us", requested == ["us"] else {
            fatalError("Expected reproduction missing")
        }
    }
}

```

## Exchange and editor probes

New diagnostics should use the real app target and independently specified expectations. The audit's generated amalgamation is omitted because it copied production sources and used synthetic boundary types. These are sufficient inputs to reproduce the observations using the normal planner, editor, and adapter entry points. Exact source anchors are in the audit.

| Case | Input and independent check | Observed at the audited baseline |
| --- | --- | --- |
| Positional self-export | Export `{{title}}` from rows with titles empty and `Old B`. Reimport with the same order and blank clearing false. Check both target IDs, the preview status for both, and executable entries. | Text exactly `# AudioMator-Metadata-Profile: 2\n\nOld B`. First target gets `Old B`, second is missing. |
| Explicit number deletion | Build a CSV plan with v2 marker, `{{trackNumber}}` and unquoted `<remove>`, baseline 3/12. Compare preview intents to typed patch and check unrelated values. | Preview lists only Track Number. Patch removes Track Number and Total Tracks. |
| Typed TXT deletion | Use v2 marker and unescaped `<remove>` with the single-column `{{trackNumber}}` text template and baseline 3/12. | Number parsing rejects the record before the token is converted. |
| Unknown advisory deletion | Supply v2 CSV with `{{contentAdvisory}}` and unquoted `<remove>` against M4A with raw advisory `170`. Check the explicit patch intent. | Ready row with nil advisory patch. |
| External CSV cell | Import a literal unmarked quoted `"'+44"` into `{{title}}`. | Plan writes `+44`. |
| Raw value array | Set `["Alpha", "Beta"]` on one raw key. Use whole-value replacement `Alpha → Changed`. Compare ordered arrays before and after. | Preview joins values and reports no change. Apply computes `["Changed", "Beta"]`. |
| Renumber adapter | Start from track 3. Independently inspect the projected payload after applying draft text `03`, `07`, or `00`. | No track patch, integer 7, and removal respectively. |

## Exchange planner benchmark

Use the production CSV planner with `{{fileName}},{{title}}` and matching synthetic file URLs. Prepare 10,000 and 100,000 matching filename/title rows, with different existing and incoming titles. Measure only the planner invocation in an optimized executable with `ContinuousClock`, consume the write-entry count, and require it to equal the number of rows. The audited harness measured four passes for each size. It prepared inputs outside the stopwatch. The 100,000-row input was 2,988,888 bytes.

| Rows | Observed planner time |
| --- | --- |
| 10,000 | 0.164–0.200 seconds |
| 100,000 | 1.83–2.87 seconds |

## Build helper fault injection

In a fresh directory place baseline copies of `scripts/codex-build.sh` and `scripts/prune-app-bundles.sh` under `scripts/`. Put test doubles on `PATH` ahead of real tools, and record their invocation and the wrapper exit status. Use no repository-root or package overrides.

| Git test double | Xcode test double | Command | Observed |
| --- | --- | --- | --- |
| `git diff` prints `AudioMator/Localizable.xcstrings`; untracked discovery empty; both return 0 | Records invocation | `bash scripts/codex-build.sh` | Exit 0 and Xcode not called. |
| Both discovery invocations exit 128 with stderr | Records invocation | `bash scripts/codex-build.sh` | Exit 0 and Xcode not called. |
| Unused | Prints `CompileAssetCatalogVariant`, `Exception while running actool`, `The file “AppIcon.icon” couldn’t be opened.`, and `Synthetic.swift:1:1: error: unrelated compiler error`; exits 65 | `bash scripts/codex-build.sh --force` | Exit 0 despite both failures. |
| Unused | Prints only the synthetic compiler error and exits 65 | `bash scripts/codex-build.sh --force` | Exit 65. |
