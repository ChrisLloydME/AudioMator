# ADR 0001: Metadata write and reload share one path reservation

- Status: Accepted for implementation
- Date: 2026-07-25

## Context

`FileMutationCoordinator` 已能对规范化路径提供原子 reservation。track renumber 在同一 reservation 中完成 fingerprint validation、write 和 reload；inspector、raw metadata、erase 与 LRCLIB 路径则在 write 返回后释放 reservation，再单独 reload。rename 或另一写入因此能在持久化与刷新之间插入。

## Decision

建立一个明确的 metadata file mutation use case，在同一路径 reservation 内完成：取消检查、expected fingerprint validation、具体 write closure 和 persisted snapshot reload。它返回结构化结果，区分 write failure、write success + reload success、write success + reload warning。`AudioViewModel` 只在主 actor 上应用 snapshot、同步 draft 并映射 presentation。

## Alternatives

- **只给 reload 再加一次 reservation**：拒绝。两个 reservation 中间仍有交错窗口，不能证明 reload 属于本次写入。
- **整个批次一次 reserve 所有文件**：拒绝。会不必要地阻塞不相交文件，扩大取消与长批次的影响；逐文件原子 write/reload 已满足一致性。
- **让每个 feature 保留自定义 helper**：拒绝。现有不一致正来自多套编排路径。

## Consequences

- rename 和同路径 metadata mutation 不会发生在 write 与 reload 之间。
- reload 失败仍不回滚成功写入，结果明确表示 disk 已改变、UI snapshot 未刷新。
- use case 需要 app-hosted fake pipeline 测试；其中可抽出的结果语义应进入快速测试。
- 多文件批次仍允许部分成功，并继续逐文件汇总。

## Verification

- continuation-controlled test 证明第二个 mutation 在第一个 reload 完成前不能执行。
- 注入 reload failure，证明结果保留 write warnings 且标记未刷新。
- 等待 reservation 时取消，证明 write closure 未执行。
- 运行 app-hosted mutation tests、SwiftPM core tests 和 macOS build。
