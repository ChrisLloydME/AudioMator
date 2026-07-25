# AudioMator 架构优化进度

## 检查点

- 审计日期：2026-07-25
- 起始 commit：`f1378c1`
- 当前 commit：`c60099b`
- 分支：`main`，启动时与 `origin/main` 一致
- 启动工作树：干净
- 当前阶段：批次 2——选择与 draft 单一所有权
- 最后稳定 commit：`c60099b`

## 当前架构假设

1. `AudioFile` 是加载到内存的磁盘快照；`SingleFileEditModel` / `MultiFileEditModel` 是未持久化 draft；TagLib 写入后的重新加载才应更新快照。
2. `AudioViewModel` 是当前文件集合、文件来源、加载任务、mutation coordinator、draft、进度与用户反馈的实际编排中心。
3. `SharedState.selectedAudioIDs` 是视图侧选择事实来源，但 `AudioViewModel.selectedAudioIDs` 又是保存和 draft 逻辑的事实来源；当前通过视图回调手动同步。
4. `FileMutationCoordinator` 对规范化路径提供原子多路径 reservation 和等待取消；批次 1 后，所有 metadata write/reload 由 `MetadataFileMutationExecutor` 保持同一 reservation。
5. `AudioMetadataPipeline` 同时声明业务所需 contract 并包含 TagLib adapter、兼容清理、验证和错误转换。
6. SwiftPM 快速测试覆盖 43 个纯逻辑用例；依赖 `AudioFile`、TagLib、Combine 或平台框架的多数编排只能在 app-hosted target 中测试。

## 已完成

### 审计基线（已提交）

- 从 `AudioMatorApp`、`ContentView`、`AudioViewModel` 追踪了文件导入、watched-folder、选择、draft、写入、reload、重命名和 provider 应用入口。
- 检查了 179 个 Swift 文件、主要依赖 import、条件编译、测试覆盖说明和 2025 年以来的修改热点。
- 确认此前可靠性修复已覆盖 stale fingerprint、mutation 等待取消、rename rollback、provider search race、部分写入失败和 watched-folder 恢复；本任务不重复这些批次。
- 形成问题矩阵、五个以内的实施批次和首个 ADR。

## 已完成批次和 commit

- 审计基线：`1a4b8c0` (`docs(audit): establish architecture modernization baseline`)
- 批次 1 contract 与测试：`7512fb1` (`arch(metadata): define atomic write and reload boundary`)
- 批次 1 调用方迁移：`c60099b` (`refactor(metadata): route writes through atomic mutations`)

## 本阶段修改文件

- `Docs/Engineering/AUDIOMATOR_ARCHITECTURE_OPTIMIZATION_PROGRESS.md`
- `Docs/Engineering/AUDIOMATOR_SYSTEM_AUDIT.md`
- `Docs/Architecture/CURRENT_ARCHITECTURE.md`
- `Docs/Architecture/DEPENDENCY_RULES.md`
- `Docs/Architecture/STATE_AND_MUTATION_MODEL.md`
- `Docs/Architecture/TEST_STRATEGY.md`
- `Docs/Architecture/Decisions/0001-atomic-write-and-reload-reservation.md`
- `AudioMator/Features/Main/Application/MetadataFileMutationExecutor.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWriteSupport.swift`
- `AudioMatorTests/FileMutationSerializationTests.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWrite.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+RawMetadataWrite.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataClear.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+LRCLIBLyricsWrite.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+TrackRenumbering.swift`
- `AudioMator/Domain/UIState/SharedState.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+FileActions.swift`
- `AudioMator/Features/Main/Views/ContentView.swift`
- `AudioMator/Features/Main/Views/ContentPane.swift`
- `AudioMator/Features/Main/Views/TrackRenumberSheet.swift`
- `AudioMator/Features/iPad/Views/IPadWorkspaceView.swift`
- `AudioMator/Features/iPad/Views/IPadInspectorView.swift`
- `AudioMator/App/Commands/ToolbarEditCommands.swift`
- `Docs/Architecture/Decisions/0002-single-selection-owner.md`

## 测试记录

- 2026-07-25：`swift test --filter AudioMatorCoreLogicTests`，43 tests passed。
- 2026-07-25：focused `FileMutationSerializationTests` 首次编译发现 XCTest async autoclosure 限制；改为先读取 actor state 后断言。
- 2026-07-25：`xcodebuild -quiet ... -only-testing:AudioMatorTests/FileMutationSerializationTests test`，passed；包含 write/reload reservation 与 reload failure 新测试。
- 2026-07-25：新增 use-case 后再次运行 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed。
- 2026-07-25：迁移后 focused `FileMutationSerializationTests`、`InspectorAndMetadataEditorWorkflowTests`、`LRCLIBLyricsTests`、`TrackRenumberExecutionTests` passed。
- 2026-07-25：迁移后 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed。
- 2026-07-25：迁移后 `bash scripts/codex-build.sh`，generic macOS universal Debug build succeeded。
- 2026-07-25：selection owner focused `InspectorAndMetadataEditorWorkflowTests` passed；编译同时暴露既有 `AudioFile.withUpdatedURL` main-actor warning，登记到批次 3。
- 2026-07-25：active Xcode 26.6 generic iOS build 未执行，原因是本机未安装 iOS 26.5 SDK；已确认 Xcode 27 beta 含 iOS 27 SDK，待用同一 `.deriveddata-codex` 验证。
- 2026-07-25：Xcode 27 beta generic iOS build 首次在 sandbox 内因 CoreSimulator/cache service 退出 143；按环境故障策略在 sandbox 外重跑（未启动 simulator），build passed，保留两个既有 iPad launch/orientation 配置 warning 待最终 release gate 评估。
- 2026-07-25：selection owner 后 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed；`bash scripts/codex-build.sh`，generic macOS universal Debug build succeeded。
- 待运行：审计文档提交前 `git diff --check`。
- 待运行：每个代码批次的相关 app-hosted 测试、SwiftPM 快速测试和增量构建。
- 待运行：目标文件要求的最终完整验证矩阵。

## 已否决或暂缓方向

- 不按文件行数机械拆分；`MetadataExchange.swift` 只有在解析、schema、export、import planning 的真实职责边界及测试入口同时迁移时才拆。
- 不创建新的 Swift module；当前收益可先通过磁盘边界、协议位置和 SwiftPM source list 获得，模块化会扩大 Xcode target 风险。
- 不建立覆盖 MusicBrainz、iTunes、LRCLIB 全部行为的通用 provider 框架；它们的查询和结果语义不同，只有写入计划与应用结果证明稳定重复时才共享。
- 不重做已由 `3b45c4a`、`f428592`、`9d3f747`、`e4be6a7` 等提交覆盖的取消、stale-file 和 retry 修复，除非新测试提供反例。
- 不修改或 vendor `TagLibAudioMetadata`。

## 未解决风险

- `AudioViewModel` 同时拥有文件来源、平台资源、加载、选择/draft、mutation、进度和 HUD，多种变化原因仍集中。
- Domain 路径内仍有 Combine、AppKit/UIKit、AVFoundation 与 TagLib 依赖；其中部分是目录归属错误，部分需要真实 adapter 拆分。
- `AudioMetadataPipeline` contract 和 TagLib 实现同文件，快速测试无法替换完整的写入—reload 用例。
- `MetadataExchange.swift` 包含多个独立语法和 planning 职责，修改扩散与 app-hosted 覆盖比例偏高。
- 没有已授权的签名、公证、上传或发布动作；“release-ready”仅指进入这些外部流程之前的源码、测试和构建状态。

## 下一步唯一动作

提交 selection 单一所有权批次，然后开始 contract/TagLib adapter 与 UIState 目录边界迁移。

## 批次规模说明

批次 1 调用方迁移涉及超过 8 个文件，因为 inspector、raw editor、erase、LRCLIB、provider 间接写入和 renumber 必须在同一检查点删除旧的 split write/reload 路径；若拆成多个行为提交，将暂时保留两套不一致 mutation contract。回滚只需回退调用方迁移 commit，`7512fb1` 的未接线 executor 不改变用户行为。

批次 2 涉及超过 8 个文件，因为两个平台的所有 selection readers/writers 必须与 owner 的 `private(set)` 同时迁移，否则任一中间提交无法编译或会恢复双事实来源。回滚该批次可完整恢复 `SharedState` mirror 与原视图同步，不触及磁盘数据。

## 恢复执行步骤

1. 阅读本文件。
2. 运行 `git status --short --branch -uall`。
3. 运行 `git log -8 --oneline --decorate`，核对“已完成批次和 commit”。
4. 只运行本文件“下一步唯一动作”；不要重复已提交批次。
5. 修改前确认最近一次已记录测试仍对应当前 commit。
