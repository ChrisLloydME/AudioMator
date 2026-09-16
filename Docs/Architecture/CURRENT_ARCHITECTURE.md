# Current Architecture

本文描述当前代码实际结构。任务进行中时，每个架构批次必须同步修正本文；完成时不得保留理想化但未实现的描述。

## Composition

`AudioMatorApp` 创建 `TagLibAudioMetadataPipeline`、`AudioViewModel`、`SharedState`、各 provider store 与工具 store，并注入 SwiftUI scene。macOS 通过独立 window 展示在线 metadata、文件名工具和 raw metadata editor；iPadOS 使用 sheet 与 session-only 文件导入。

## Layers

- `App`：应用入口、scene、commands、notifications、macOS delegate 与更新装配。
- `Features`：SwiftUI/AppKit/UIKit 视图、provider store、工具 store、`AudioViewModel`、feature state 及 mutation presentation。
- `Domain`：metadata/rename/exchange/renumber 语义、`AudioFile`/draft 模型与 metadata pipeline contract。`AudioFile` retains the package's `MetadataFileVersion` token so edit sessions can participate in transaction-boundary optimistic concurrency; other editable tag representation remains behind the pipeline contract.
- `Infrastructure`：watched-folder、directory monitor、网络 client、update service、provider core，以及 `Infrastructure/TagLib` 下的 metadata pipeline 与 `AudioFile` loading adapter。

## Runtime flow

文件由 quick import 或 watched-folder scan 进入 `AudioViewModel` 私有集合，再通过 `files` 暴露当前 source。`AudioViewModel` 是选择的唯一 owner；`setSelectedAudioIDs` 过滤不可见 ID，并在同一 main-actor operation 中重建 single/multi inspector draft。所有 metadata mutation 通过 `MetadataFileMutationExecutor` 在同一 `FileMutationCoordinator` reservation 内完成 fingerprint validation 和不可取消的同步 write。成功后 reload 也在 reservation 内尝试；只有 reload deadline 到达时才释放 reservation 并返回“已写入但未刷新”，而不会把仍可能提交的 write 误报为 timeout。

rename 是多路径两阶段事务：同时 reserve source/destination，先移动到唯一临时路径，再 finalize；失败时 best-effort rollback 并返回 recovery items。

provider search 由各自 `@MainActor` store 管理。MusicBrainz/iTunes 生成 write plan 并交给 `AudioViewModel`；LRCLIB 通过只包含 `LYRICS` 的 `RawMetadataPatch` 更新歌词，不重写整个 PropertyMap。网络调用保持用户显式触发。

## Adapter boundary

`Domain/MetadataEditing/AudioMetadataPipeline.swift` 声明 write/load contract、payload、精确 raw value map 和结果。`Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift` 把 app intent 转为 package `MetadataPatch` / `RawMetadataPatch`; container aliases, advisory representation, number-pair storage, verification, and atomic commit remain package responsibilities. `AudioFile+TagLibLoading.swift` uses the package snapshot as the editable-tag authority and AVFoundation only for technical/display enrichment. App 在 composition root 注入具体 adapter。

Metadata exchange 按职责分为 `MetadataExchangeModels`（字段 schema/校验）、`MetadataExchangeTemplate`（字段映射）、`MetadataExchangeTemplateSyntax`（纯模板 tokenizer）和 `MetadataExchangePlanning`（export/import plan 与 matcher）。SwiftPM 直接编译 production syntax parser、CSV parser、resource budget 与 locator index。
