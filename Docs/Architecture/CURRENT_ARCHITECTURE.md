# Current Architecture

本文描述当前代码实际结构。任务进行中时，每个架构批次必须同步修正本文；完成时不得保留理想化但未实现的描述。

## Composition

`AudioMatorApp` 创建 `TagLibAudioMetadataPipeline`、`AudioViewModel`、`SharedState`、各 provider store 与工具 store，并注入 SwiftUI scene。macOS 通过独立 window 展示在线 metadata、文件名工具和 raw metadata editor；iPadOS 使用 sheet 与 session-only 文件导入。

## Layers

- `App`：应用入口、scene、commands、notifications、macOS delegate 与更新装配。
- `Features`：SwiftUI/AppKit/UIKit 视图、provider store、工具 store、`AudioViewModel`、feature state 及 mutation presentation。
- `Domain`：metadata/rename/exchange/renumber 语义、`AudioFile`/draft 模型与 metadata pipeline contract。`AudioFile` 模型本身只依赖 Foundation；其他仍含 Combine 的观察型 domain models 是后续可独立评估的边界。
- `Infrastructure`：watched-folder、directory monitor、网络 client、update service、provider core，以及 `Infrastructure/TagLib` 下的 metadata pipeline 与 `AudioFile` loading adapter。

## Runtime flow

文件由 quick import 或 watched-folder scan 进入 `AudioViewModel` 私有集合，再通过 `files` 暴露当前 source。`AudioViewModel` 是选择的唯一 owner；`setSelectedAudioIDs` 过滤不可见 ID，并在同一 main-actor operation 中重建 single/multi inspector draft。所有 metadata mutation 通过 `MetadataFileMutationExecutor` 在同一 `FileMutationCoordinator` reservation 内完成 fingerprint validation、write 和 reload，再由 `AudioViewModel` 在主 actor 应用新的 `AudioFile` 快照与 presentation。

rename 是多路径两阶段事务：同时 reserve source/destination，先移动到唯一临时路径，再 finalize；失败时 best-effort rollback 并返回 recovery items。

provider search 由各自 `@MainActor` store 管理。MusicBrainz/iTunes 生成 write plan 并交给 `AudioViewModel`；LRCLIB 更新 raw property map。网络调用保持用户显式触发。

## Adapter boundary

`Domain/MetadataEditing/AudioMetadataPipeline.swift` 只声明 write/load contract、payload 和结果。`Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift` 实现 TagLib 写入、验证与兼容清理；`AudioFile+TagLibLoading.swift` 拥有 TagLib、AVFoundation 与平台图像构造。App 在 composition root 注入具体 adapter。

Metadata exchange 按职责分为 `MetadataExchangeModels`（字段 schema/校验）、`MetadataExchangeTemplate`（字段映射）、`MetadataExchangeTemplateSyntax`（纯模板 tokenizer）和 `MetadataExchangePlanning`（export/import plan 与 matcher）。SwiftPM 直接编译 production syntax parser、CSV parser、resource budget 与 locator index。
