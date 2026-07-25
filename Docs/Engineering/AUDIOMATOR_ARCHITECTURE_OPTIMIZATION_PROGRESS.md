# AudioMator 架构优化进度

## 检查点

- 审计日期：2026-07-25
- 起始 commit：`f1378c1`
- 当前 commit：`1a4b8c0`
- 分支：`main`，启动时与 `origin/main` 一致
- 启动工作树：干净
- 当前阶段：批次 1——原子 metadata write/reload use case（contract 与测试）
- 最后稳定 commit：`1a4b8c0`

## 当前架构假设

1. `AudioFile` 是加载到内存的磁盘快照；`SingleFileEditModel` / `MultiFileEditModel` 是未持久化 draft；TagLib 写入后的重新加载才应更新快照。
2. `AudioViewModel` 是当前文件集合、文件来源、加载任务、mutation coordinator、draft、进度与用户反馈的实际编排中心。
3. `SharedState.selectedAudioIDs` 是视图侧选择事实来源，但 `AudioViewModel.selectedAudioIDs` 又是保存和 draft 逻辑的事实来源；当前通过视图回调手动同步。
4. `FileMutationCoordinator` 对规范化路径提供原子多路径 reservation 和等待取消，但除 track renumber 外，写入与 reload 没有处于同一 reservation 内。
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

## 测试记录

- 2026-07-25：`swift test --filter AudioMatorCoreLogicTests`，43 tests passed。
- 2026-07-25：focused `FileMutationSerializationTests` 首次编译发现 XCTest async autoclosure 限制；改为先读取 actor state 后断言。
- 2026-07-25：`xcodebuild -quiet ... -only-testing:AudioMatorTests/FileMutationSerializationTests test`，passed；包含 write/reload reservation 与 reload failure 新测试。
- 2026-07-25：新增 use-case 后再次运行 `swift test --filter AudioMatorCoreLogicTests`，43 tests passed。
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

- 写入与 reload reservation 分裂，rename 或另一写入可在两者之间发生。
- 选择状态有两个可变事实来源，draft 依赖视图及时同步。
- `AudioViewModel` 同时拥有文件来源、平台资源、加载、选择/draft、mutation、进度和 HUD，多种变化原因仍集中。
- Domain 路径内仍有 Combine、AppKit/UIKit、AVFoundation 与 TagLib 依赖；其中部分是目录归属错误，部分需要真实 adapter 拆分。
- `AudioMetadataPipeline` contract 和 TagLib 实现同文件，快速测试无法替换完整的写入—reload 用例。
- `MetadataExchange.swift` 包含多个独立语法和 planning 职责，修改扩散与 app-hosted 覆盖比例偏高。
- 没有已授权的签名、公证、上传或发布动作；“release-ready”仅指进入这些外部流程之前的源码、测试和构建状态。

## 下一步唯一动作

完成并提交 `MetadataFileMutationExecutor` contract 与 reservation/reload failure tests，然后迁移所有 metadata mutation 调用方。

## 恢复执行步骤

1. 阅读本文件。
2. 运行 `git status --short --branch -uall`。
3. 运行 `git log -8 --oneline --decorate`，核对“已完成批次和 commit”。
4. 只运行本文件“下一步唯一动作”；不要重复已提交批次。
5. 修改前确认最近一次已记录测试仍对应当前 commit。
