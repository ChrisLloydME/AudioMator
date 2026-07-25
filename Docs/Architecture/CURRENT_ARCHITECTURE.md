# Current Architecture

本文描述当前代码实际结构。任务进行中时，每个架构批次必须同步修正本文；完成时不得保留理想化但未实现的描述。

## Composition

`AudioMatorApp` 创建 `TagLibAudioMetadataPipeline`、`AudioViewModel`、`SharedState`、各 provider store 与工具 store，并注入 SwiftUI scene。macOS 通过独立 window 展示在线 metadata、文件名工具和 raw metadata editor；iPadOS 使用 sheet 与 session-only 文件导入。

## Layers

- `App`：应用入口、scene、commands、notifications、macOS delegate 与更新装配。
- `Features`：SwiftUI/AppKit/UIKit 视图、provider store、工具 store、`AudioViewModel` 及 mutation presentation。
- `Domain`：metadata/rename/exchange/renumber 语义和当前 `AudioFile`/draft 模型。基线状态下该目录仍包含 UI state 及部分平台/TagLib 依赖，属于已登记改进项。
- `Infrastructure`：watched-folder、directory monitor、网络 client、update service 和 provider core。基线 `TagLibAudioMetadataPipeline` 尚位于 Domain 文件中。

## Runtime flow

文件由 quick import 或 watched-folder scan 进入 `AudioViewModel` 私有集合，再通过 `files` 暴露当前 source。选择由 `SharedState` 保存，并复制到 `AudioViewModel`；后者据此创建 inspector draft。metadata mutation 通过 `FileMutationCoordinator` 串行化相同规范化路径，调用 `AudioMetadataPipeline` 写入，再 reload 为新的 `AudioFile` 快照。

rename 是多路径两阶段事务：同时 reserve source/destination，先移动到唯一临时路径，再 finalize；失败时 best-effort rollback 并返回 recovery items。

provider search 由各自 `@MainActor` store 管理。MusicBrainz/iTunes 生成 write plan 并交给 `AudioViewModel`；LRCLIB 更新 raw property map。网络调用保持用户显式触发。

## Known transitional boundaries

- metadata write/reload reservation 在不同 feature path 中不一致。
- selection 存在两个可变 owner。
- metadata pipeline contract 与 TagLib adapter 尚未物理分离。
- `Domain/UIState` 属于目录边界错误。

这些项目只有在代码和测试实际迁移后才从本节删除。
