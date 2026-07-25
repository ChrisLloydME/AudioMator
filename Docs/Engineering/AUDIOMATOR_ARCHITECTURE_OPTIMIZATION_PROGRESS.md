# AudioMator 架构优化进度

## 检查点

- 审计日期：2026-07-25
- 起始 commit：`f1378c1`
- 当前 commit：`HEAD`（release evidence；implementation/tooling checkpoint 为 `c40dd32`）
- 分支：`main`，启动时与 `origin/main` 一致
- 启动工作树：干净
- 当前阶段：批次 5——故障注入与最终 release gate
- 最后稳定 commit：`HEAD`

## 当前架构假设

1. `AudioFile` 是加载到内存的磁盘快照；`SingleFileEditModel` / `MultiFileEditModel` 是未持久化 draft；TagLib 写入后的重新加载才应更新快照。
2. `AudioViewModel` 是当前文件集合、文件来源、加载任务、mutation coordinator、draft、进度与用户反馈的实际编排中心。
3. `AudioViewModel.selectedAudioIDs` 是选择的唯一事实来源；setter 在同一 main-actor operation 中过滤可见 ID 并重建 draft。
4. `FileMutationCoordinator` 对规范化路径提供原子多路径 reservation 和等待取消；批次 1 后，所有 metadata write/reload 由 `MetadataFileMutationExecutor` 保持同一 reservation。
5. `AudioMetadataPipeline` 在 Domain 声明业务 contract；TagLib adapter、兼容清理、验证和 `AudioFile` loading 位于 `Infrastructure/TagLib`。
6. SwiftPM 快速测试覆盖 47 个纯逻辑用例；依赖 `AudioFile`、TagLib、Combine 或平台框架的多数编排由 app-hosted target 测试。

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
- 批次 2 selection owner：`585e8ba` (`refactor(selection): establish a single session owner`)
- 批次 3 UI state boundary：`a9634da` (`refactor(ui-state): move presentation state out of domain`)
- 批次 3 metadata adapter boundary：`ac4b343` (`refactor(metadata): separate domain contracts from TagLib`)
- 批次 4 exchange responsibility boundary：`38dbe70` (`refactor(exchange): separate syntax from planning`)
- 批次 5 reliability sensors：`f5167df` (`test(reliability): cover provider and missing-file faults`)
- 批次 5 release tooling：`c40dd32` (`chore(release): restore binary TagLib smoke tooling`)
- 最终 release evidence：`HEAD` (`docs(release): record architecture readiness evidence` 及本记录收口)

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
- `AudioMator/Features/Main/State/SharedState.swift`
- `AudioMator/Features/Main/State/MiddleListColumn.swift`
- `AudioMator/Features/Main/State/ToolbarButtonOption.swift`
- `AudioMator/Features/Main/State/InspectorMetadataField.swift`
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
- 2026-07-25：UI-only state 迁移后 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed；`bash scripts/codex-build.sh`，generic macOS universal Debug build succeeded；`git diff --check` passed。
- 2026-07-25：metadata contract/adapter 拆分后 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed；首次 macOS build 发现 Infrastructure loader 缺显式 AppKit/UIKit import，修正后 `bash scripts/codex-build.sh` passed。
- 2026-07-25：focused `SensitiveLoggingPolicyTests` 与 `TagLibReadWriteIntegrationTests` passed；仅保留测试代码中两个既有 unused-result warning。
- 2026-07-25：Xcode 27 beta generic iOS build passed（未启动 simulator）；仍保留批次 2 已登记的 orientation/launch configuration warning，留待最终 release gate 修正。
- 2026-07-25：Metadata Exchange 拆分后固定 seed 测试首次揭示“仅含空字段的末行”与尾随换行不可区分；生成器排除该格式歧义后，47 个 SwiftPM tests passed。
- 2026-07-25：Metadata Exchange 首次并行启动两个共享 DerivedData 的 Xcode command，test 因 build DB lock 取消；串行重跑后 `bash scripts/codex-build.sh` 与 focused `MetadataExchangeTests` passed。
- 2026-07-25：新增 provider fault sensors；focused `ProviderNetworkFaultTests` passed，覆盖 MusicBrainz/iTunes/LRCLIB timeout、non-2xx 与 invalid payload。
- 2026-07-25：新增 deleted-source rename sensor；首次断言错误地预期空 recovery list，实际返回可操作的 `location unknown` recovery item；按真实 contract 修正后 focused `FileRenameTransactionTests` passed。
- 2026-07-25：把 iPad 四方向与 `UILaunchScreen` 写入实际 `Config/Info.plist` 后，Xcode 27 beta generic iOS build passed 且原 orientation/launch warnings 清零；产物 plist 已核对。
- 2026-07-25 最终矩阵：47 SwiftPM tests passed；`bash scripts/codex-build.sh --force` passed；完整串行 app-hosted suite 264 tests passed；generic macOS build passed；Xcode 27 beta generic iOS build passed 且无输出 warning。
- 2026-07-25 临时夹具 smoke：FLAC/M4A/MP3/OGG/WAV read/raw、批量 write-roundtrip/reload、Unicode rename/reload 全部 passed；缺失源文件按预期非零失败；临时目录已删除。
- 2026-07-25 remote gate：`git ls-remote` 确认 `origin/main` 为 `a9634da...`，远端最新稳定 tag `V2.4.2B26521` 为 `a28822b...`；本地后续 commit 未 push。
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
- Domain 路径内仍有 Combine 观察型模型；将其改为 Observation 会扩散 UI binding，需另有证据再做。
- metadata contract 与 adapter 已物理分离，但真实 TagLib write/reload 仍必须由 app-hosted target 覆盖。
- Metadata exchange planning 仍依赖真实 `AudioFile` 与本地化字段 schema，因此完整 plan 保留 app-hosted 覆盖；纯 syntax/CSV/index 已进入 SwiftPM。
- 没有已授权的签名、公证、上传或发布动作；“release-ready”仅指进入这些外部流程之前的源码、测试和构建状态。

## 下一步唯一动作

目标完成；后续仅在明确授权下 push、tag、签名、公证、上传或发布。

## 批次规模说明

批次 1 调用方迁移涉及超过 8 个文件，因为 inspector、raw editor、erase、LRCLIB、provider 间接写入和 renumber 必须在同一检查点删除旧的 split write/reload 路径；若拆成多个行为提交，将暂时保留两套不一致 mutation contract。回滚只需回退调用方迁移 commit，`7512fb1` 的未接线 executor 不改变用户行为。

批次 2 涉及超过 8 个文件，因为两个平台的所有 selection readers/writers 必须与 owner 的 `private(set)` 同时迁移，否则任一中间提交无法编译或会恢复双事实来源。回滚该批次可完整恢复 `SharedState` mirror 与原视图同步，不触及磁盘数据。

批次 4 的代码与文档超过 8 个文件，因为删除旧聚合文件、创建四个职责文件、SwiftPM source list、固定-seed tests、ADR 与架构/测试记录必须在同一可编译检查点保持一致。回滚该 commit 可恢复原聚合文件和 43-test 快速边界，不改变持久化格式。

## 恢复执行步骤

1. 阅读本文件。
2. 运行 `git status --short --branch -uall`。
3. 运行 `git log -8 --oneline --decorate`，核对“已完成批次和 commit”。
4. 只运行本文件“下一步唯一动作”；不要重复已提交批次。
5. 修改前确认最近一次已记录测试仍对应当前 commit。
