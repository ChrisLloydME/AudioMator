# State and Mutation Model

## State categories

| Category | Meaning | Persistence |
| --- | --- | --- |
| file identity | session UUID associated with a normalized path; rename explicitly rebinds path while retaining ID | session |
| disk snapshot | immutable `AudioFile` values loaded from current bytes/tags | recreated after import, scan or mutation |
| selection | IDs selected in the current visible collection | session |
| editing draft | `SingleFileEditModel` / `MultiFileEditModel`, distinct from disk snapshot | session, never implicit disk truth |
| presentation | progress, HUD, open sheet/window and issue summaries | session, except explicit issue-log storage |
| source configuration | watched-folder bookmark records and display preferences | user defaults/bookmark store on supported platform |

基线例外：selection 当前同时存在于 `SharedState` 与 `AudioViewModel`。批次 2 将移除这一例外。

## File identity

- URL key 使用 standardized、symlink-resolved、Unicode precomposed path。
- import/rescan 通过 `fileIDsByKey` 保留同路径 ID。
- rename plan 携带 ID、source/destination 和 preview fingerprint；事务成功后 ID 保持不变并更新 URL mapping。
- metadata plan 和 provider plan 携带 expected fingerprint；开始写入前必须再次验证。

## Mutation lifecycle

```text
prepare immutable input + expected fingerprint
  → reserve every affected normalized source/destination path
  → check cancellation
  → validate current file identity
  → execute disk mutation
  → reload persisted snapshot while reservation is still held
  → release reservation
  → publish snapshot/result on MainActor
```

rename 的多文件 move 使用同一 reservation 中的两阶段事务和 best-effort rollback。metadata 批次默认逐文件提交，因此允许部分成功；结果必须保留每个文件的失败和 warning，不能把已写入但 reload 失败报告成“未写入”。

## Cancellation and recovery

- 等待 reservation 时取消：operation 不得稍后执行。
- reservation 获取后取消：在进入不可逆写入前检查；写入开始后以真实持久化结果为准，不伪称已回滚。
- write 失败：disk snapshot 与 draft 保持原状并返回 failure。
- write 成功、reload 失败：返回 persisted-with-refresh-warning；内存不得伪造新 snapshot，用户可以重新加载。
- rename rollback 不完整：返回每个 operation 的实际候选位置和 rollback errors，要求人工恢复。
- 文件移动、替换或删除：fingerprint 或 load 失败应关闭写入，不自动寻找“看起来相同”的替代文件。
