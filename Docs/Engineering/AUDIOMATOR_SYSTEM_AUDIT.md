# AudioMator 系统审计

## 审计范围与基线

- 日期：2026-07-25
- 起始 commit：`f1378c1`
- 最终 commit：任务完成时填写
- 源码规模：179 个 Swift 文件，约 54,648 行（含测试）
- 快速测试基线：43 tests passed
- 证据优先级：当前代码和当次测试 > Git 历史 > 既有说明文档

## 当前调用和依赖模型

```text
AudioMatorApp
  ├─ constructs TagLibAudioMetadataPipeline / AudioViewModel / feature stores
  └─ ContentView
       ├─ SharedState (sidebar, selection, ordering, preferences)
       ├─ AudioViewModel (files, a second selection, drafts, loading, mutations, feedback)
       ├─ MetadataEditorStore ── AudioMetadataPipeline
       └─ provider stores ── concrete network clients

AudioViewModel write extensions
  ├─ fingerprint validation
  ├─ FileMutationCoordinator reservation
  ├─ AudioMetadataPipeline ── TagLibAudioMetadata
  ├─ reload AudioFile
  └─ replace loaded snapshot / refresh inspector / present result
```

总体依赖方向尚未完全达到目标：App 正确完成主要装配，但 Features 直接依赖同时含 contract 和 TagLib 实现的 Domain 文件；Domain 下的 `AudioFile` 与 UIState 类型又直接依赖平台/观察框架。

## 核心流程模型

| 流程 | owner / 入口 | mutation 与结果路径 | 当前证据 |
| --- | --- | --- | --- |
| quick import | `AudioViewModel.addQuickImportFiles` | generation + per-URL token；后台 load；失败按当前 token 汇总 | `QuickImportCancellationTests` 覆盖移除/替换后的陈旧完成 |
| watched folders | `AudioViewModel` | bookmark store、security scope、directory monitor、debounced rescan、失败时保留旧快照 | 多个近期 watched-folder 修复及 `DirectoryMonitoringPlanTests` |
| selection / draft | `SharedState` + `AudioViewModel` | view `onChange` 双向同步；`updateEditForSelection` 重建 draft | 两个公开可写 `selectedAudioIDs` 是双事实来源 |
| inspector / batch write | `AudioViewModel+MetadataWrite` | validate → reserved write → release → reload → replace snapshot → HUD | write 和 reload 之间存在交错窗口 |
| raw / lyrics / erase | feature-specific extensions | 与 inspector 类似，但各自重复 summary、reload warning、draft refresh | 结果语义相似但编排分散 |
| track renumber | `AudioViewModel+TrackRenumbering` | validate → reserved write + reload → batch replace | 唯一已经将 write/reload 纳入同一 reservation 的路径 |
| rename | `AudioViewModel+FileRename` | 原子 reserve 所有 source/destination；两阶段 move；best-effort rollback；更新 ID/path | source fingerprint、cycle 与 rollback 已测试 |
| metadata exchange | `MetadataExchangePlanner` + tool store + AudioViewModel plan write | parse/match/plan 后转 `SingleFileEditModel` 写入 | planner 文件同时含 field schema、模板语法、export/import planning |
| providers | provider store → tagging plan → `AudioViewModel` | 各 provider 独立搜索；MusicBrainz/iTunes 最终复用 metadata plan write，LRCLIB 走 raw map | 搜索 restart race 已测试；写入结果仍分两套 |
| iPad lifecycle | `AudioMatorApp` / `ContentView` / iPad views | session-only imports 与 security scope；不持久化 watched folders | 产品差异主要位于 Features/App，但共享状态中仍有条件编译 |

## 状态所有权审计

| 状态 | 当前 owner | writers | 生命周期 / 持久化 | actor 边界 | 结论 |
| --- | --- | --- | --- | --- | --- |
| loaded file snapshots | `AudioViewModel` 的 quick/watched collections | import、rescan、reload、rename | session；watched-folder 配置另行持久化 | `@MainActor` | owner 明确，但与来源/编排同类过载 |
| visible files | `AudioViewModel.files` | `rebuildVisibleFiles` | 派生/session | `@MainActor` | 应保持派生，不作为磁盘事实 |
| selection | `SharedState` 和 `AudioViewModel` | Content/iPad/table/commands | session | 实际均主线程但 `SharedState` 未标 `@MainActor` | P1 双事实来源 |
| inspector draft | `AudioViewModel.edit` / `multiEdit` | selection sync、fields、artwork actions、reload | session/未持久化 | `@MainActor` | 与 disk snapshot 已有概念区分，owner 仍与大 VM 绑定 |
| disk state | 文件系统 + TagLib | mutation extensions / rename | 持久化 | detached work + coordinator | write/reload contract 不一致 |
| mutation reservations | `FileMutationCoordinator` actor | 每个写 helper 与 rename | operation scoped | actor | 原子多 key、取消语义已有测试 |
| save progress / HUD / issue log | `AudioViewModel` + `SaveIssueLogStore` | 各 mutation path | HUD/session；issue log 持久化 | `@MainActor` | presentation 与 use-case result 混合 |
| provider search state | 各 provider store | search/cancel/restart | feature session | `@MainActor` + Task | provider 独立合理；共享写入结果可收敛 |

## 问题矩阵

评分 0–3：0 无实质证据，3 高风险或高收益。总分只用于排序，不替代工程判断。

| ID | 问题 | Cor | Data | Amp | Coh | Coup | State | Test | Conc | Plat | Oper | 总分 | 优先级 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| A1 | 多数 metadata 路径在 write 后释放 reservation，再单独 reload | 3 | 3 | 3 | 2 | 2 | 3 | 3 | 3 | 1 | 3 | 26 | P1 |
| A2 | `selectedAudioIDs` 在 SharedState / AudioViewModel 双重可写 | 3 | 1 | 3 | 3 | 2 | 3 | 2 | 2 | 2 | 2 | 23 | P1 |
| A3 | `AudioViewModel` 同时负责来源、资源、加载、选择、draft、mutation 和反馈 | 2 | 2 | 3 | 3 | 3 | 3 | 3 | 2 | 3 | 2 | 26 | P2-high |
| A4 | `AudioMetadataPipeline.swift` 混合 contract、domain payload、TagLib adapter 和兼容清理 | 2 | 3 | 3 | 3 | 3 | 1 | 3 | 2 | 2 | 3 | 25 | P2-high |
| A5 | `Domain/UIState` 与 `AudioFile` 含 Combine/平台依赖 | 1 | 1 | 2 | 3 | 3 | 2 | 3 | 1 | 3 | 1 | 20 | P2-high |
| A6 | `MetadataExchange.swift` 聚合字段 schema、模板 parser、export/import planner 与 matcher | 2 | 2 | 3 | 3 | 2 | 1 | 3 | 1 | 1 | 2 | 20 | P2-high |
| A7 | provider 搜索/匹配模型相似但语义不同 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 17 | 暂缓 |
| A8 | 快速测试排除真实 write/reload use case 与 production exchange planner | 2 | 2 | 3 | 2 | 2 | 2 | 3 | 2 | 1 | 2 | 21 | 随批次解决 |

实施状态：A1 已在批次 1 收敛到 `MetadataFileMutationExecutor`；所有 metadata、raw map、erase、LRCLIB 和 renumber 调用方均在同一路径 reservation 中完成 write/reload。A2 已在批次 2 收敛到 `AudioViewModel.setSelectedAudioIDs`，并移除 `SharedState` 的镜像选择与视图同步回调。A5 的 UI-only 部分已通过把四个 `Domain/UIState` 文件迁入 `Features/Main/State` 解决；`AudioFile` adapter 隔离仍开放。其余条目保持开放。

## 获选批次

1. **原子文件 mutation use case**：先测试交错，再统一 validate/write/reload reservation 与明确的 persisted/refresh-failed/failure 结果；保持 rename 事务不变量。
2. **选择与 draft 单一所有权**：去除选择双写同步；将文件会话状态的 writer 收敛到一个主 actor owner，保持现有 UI binding 行为。
3. **依赖方向修正**：把 metadata contract/domain values 与 TagLib adapter 拆开；把 UI-only state 移出 Domain；只迁移有真实边界收益的 `AudioViewModel` 职责。
4. **Metadata Exchange 职责与快速测试边界**：按 schema/template/export/import planning 拆分，生产 planner 直接进入可复现测试；加入固定 seed 的 parser/escaping/Unicode/索引属性测试。
5. **故障注入、provider 写入语义与最终收口**：补齐 write 成功但 reload 失败、等待取消、路径移动/删除、网络 timeout/non-2xx/invalid response 等回归；仅在证据支持时共享 provider apply contract；删除旧 helper 并完成 release gate。

每个批次都必须独立构建、验证和回滚。超过 8 个文件时，在进度文档中记录不可进一步拆分的理由。

## 保持的不变量

- track/disc 数字和用户文本意图继续作为结构化字段处理，容器合法规范化不是自动失败。
- erase-all 保持 best effort。
- 只操作临时目录中的测试夹具副本。
- macOS 保留 watched folders 和桌面行为；iPadOS 保持 session-only。
- 网络功能保持显式、用户发起。
- 文件 ID 在正常 reload 和 rename 后保持稳定；路径改变必须通过显式 rename 结果更新。

## 历史证据

2025 年以来的高修改扩散区域包括旧/新 `AudioViewModel`、metadata write 扩展、`MetadataExchange.swift`、`AudioFile`、`ContentView`、MusicBrainz client 和 app-hosted workflow tests。近期历史同时表明项目已完成多轮可靠性修复；因此本审计选择统一边界和新失败传感器，而不是再次机械拆大文件。
