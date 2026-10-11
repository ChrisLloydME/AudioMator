# Metadata and main-list performance investigation

Date: 2026-10-11. Starting revision: `845296d`.

## Findings and fixes

The conflict resolver introduced in `8b311f9` read a full raw/structured snapshot
for every Inspector and Metadata Editor save, including unchanged revisions. The
transactional writer also performs its own preservation and verification reads.
The resolver now checks file identity and the opaque filesystem version first.
An unchanged version writes the exact delta against its existing baseline;
changed versions still use the full conflict-resolution path. Every write retains
the dependency's final expected-version guard. No-op saves also recheck the version.

Loading always asked AVFoundation for metadata solely to find display-only ID3
TEXT (Credits), even after reading TagLib's full snapshot. For MP3/MP2, WAV,
AIFF/AIF and TTA, the snapshot's raw frames establish whether TEXT exists. MP4
and Ogg containers do not have that ID3 surface. These cases now skip unnecessary
AVFoundation metadata reads. FLAC, ADTS and other formats retain the fallback;
technical-property fallbacks and before/after revision validation remain intact.

The major batch-save bottleneck was collection publication after each successful
reload: replacing one file rebuilt the complete visible list and ID lookup, then
invalidated table presentation and Inspector state. Saving N selected files
therefore repeatedly processed the entire N-file collection. Reloads are now
published together, after 32 accepted files or 200 ms, and flushed before batch
completion, failure/cancellation cleanup, or a new progress operation. The actual
write/reload transaction and per-file outcome remain independent. A pending
readback is immediately available to the Inspector retry baseline; generation
checks still reject older completions. New immediate refreshes supersede queued
snapshots, and removing a file prevents its queued reload from restoring it.

Progress updates also invalidate the window. Intermediate progress publications
are now bounded to about 10 per second, with the final completed count immediate.

For large range selections, the 2,048-entry pairwise artwork cache could evict
all earlier comparisons before revisiting them. An additional bounded group of
immutable snapshot IDs records covers already proven exactly equal. Extending a
selection or changing its first row reuses that proof; a new snapshot still
compares complete bytes. No sampled hashes or approximate artwork equality are used.

## Non-interactive measurements

`MainMetadataFlowPerformanceTests` injects fake metadata into the real
AudioViewModel, native table selection delegate, Inspector draft, batch-save loop,
mutation coordinator, write/reload executor and collection observer. Its fake
pipeline cannot change audio files or contact the network. Progress observers
also reevaluate table/merged Inspector data. Times are informational; regression
gates check write/load counts, output metadata, preserved selection, clean drafts
and bounded publication work.

| Scenario | Before publication coalescing | After |
| --- | --- | --- |
| 1,000-file save | 5.02 s; 1,000 collection publications | About 0.5 s; 32 publications |
| 4,000-file save | Did not finish in 45 s; only 2,654 publications/targets completed | About 3.4–5.6 s; 126 publications |
| Single-row selection, 1,000/4,000 files, no cover | Median about 0.03 ms | Median about 0.03 ms |
| 64 independent identical 2 MiB covers | First exact comparison: 13.88 ms | Changing/restoring the range anchor: about 0.65 ms |

The 4,000-file baseline deliberately stopped waiting at its deadline; it is not
a completed save timing. The final regression harness allows 120 seconds to
avoid treating a loaded test runner as a performance failure. The fake pipeline
subsequently moved snapshot construction onto the main actor to remove concurrency
warnings; timings across those versions are approximate. Selection measurements
exercise native delegate/model work, not whole-window rendering or user-perceived
latency. First uncached exact artwork comparison still examines complete payloads.

`MetadataIOPerformanceTests` writes temporary copies of all six committed audio
formats and records TagLib snapshot, AVFoundation metadata, full load, resolved
save and direct transactional save stages. Initial local fixture measurements
showed resolved saves falling from roughly 2.2–4.3 ms to 1.7–3.3 ms. Ordinary
version-stable saves now require zero adapter-level conflict snapshots, rather
than one. A generated 32 MiB MP3 also loads, saves and reloads successfully. Tiny
warm fixtures and a synthetic long recording do not establish throughput for
network volumes, file providers or every real library; filesystem copy and
durability-sync costs remain in the transactional writer.

## Verification

- Complete serial app-hosted suite: 436 tests passed.
- After removing isolation warnings from the new benchmarks, all 23 focused
  benchmark, artwork and mutation-order tests passed again.
- Final repository-script incremental macOS build: successful.
- New coverage includes no-extra-snapshot saves and no-ops, permission changes,
  final-guard races for typed/raw writes, Credits equivalence with AVFoundation,
  large synthetic selection/save flows, queued reload ordering/removal, and a
  3,000-file artwork group exceeding the old pair-cache capacity.
- A new cache test initially caught loss of the first row's equality proof after
  shrinking then restoring a large selection. The group now retains the ordinary
  cache budget in addition to the current selection; the repaired test passes.
- No computer use, interactive app launch, screenshots or UI visual acceptance.
- No external TagLibAudioMetadata repository or package source was modified.

Run the app-hosted benchmarks serially with the `AudioMator` scheme and
`.deriveddata-codex`, using `-only-testing:AudioMatorTests/MetadataIOPerformanceTests`
or `-only-testing:AudioMatorTests/MainMetadataFlowPerformanceTests`.
