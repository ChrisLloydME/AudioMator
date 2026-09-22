# Test Strategy

## Fast core tests

命令：`swift test --filter AudioMatorCoreLogicTests`

职责：Foundation-only 的 metadata 语义、track/disc、rename planning、CSV/模板、排序、provider query/ranking、resource limits 和纯 use-case result。测试必须确定性、无网络、无 TagLib、无 UI framework。

属性/模糊测试使用固定 seed、明确迭代次数和输入长度上限。失败输出 seed 与最小必要输入，使 CI 可复现。

当前固定-seed 性质传感器覆盖 CSV quote/delimiter/formula/Unicode round-trip、metadata template syntax code-point preservation、track/disc numeric intent、rename unsafe scalar 清理；全空末尾 CSV record 因文本格式本身与尾随换行不可区分，生成器明确排除该歧义输入。

## App-hosted tests

命令：

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
```

职责：TagLib adapter、真实 `AudioFile` loading、temporary fixture copies、main-actor state orchestration、mutation serialization、security scope adapter、platform presentation mapping。所有音频写入只使用临时目录中的 fixture 副本。

测试目录按失败语义和架构层组织，同时保留单一 app-hosted target：

- `Unit/Core` 与 `Unit/Presentation`：无外部 I/O 的值语义和显示映射；
- `Application`：metadata editing、rename、metadata exchange、watched-folder orchestration；
- `Integration/TagLib` 与 `Integration/Network`：真实 adapter/fixture 和受控 provider 边界；
- `Concurrency`：reservation、取消和 stress 行为；
- `Performance`：吞吐量与响应性测量；
- `TestSupport`：跨文件共享且边界明确的 fixture factory。

目录层级用于可发现性，不改变 XCTest target 或并行策略。仍在根目录的测试含有仓库路径策略或跨层 contract，移动前需先去除该耦合。

## Fault injection

使用 protocol fake/spy、continuation gate 和临时目录覆盖：

- write 失败与批次中途失败；
- write 成功但 reload 失败；
- 等待 mutation reservation 时取消；
- 相同路径和 source/destination alias 并发；
- 文件被移动、替换或删除；
- rename finalize/rollback 失败；
- provider timeout、取消、non-2xx、无效响应和旧请求晚完成；
- security-scoped access acquisition 失败或作用域提前结束。

## Build matrix

- 每批：相关测试 + SwiftPM 快速测试 + `bash scripts/codex-build.sh`（涉及 app code 时）。
- 最终：目标文件列出的 SwiftPM、强制 build、完整 macOS tests、generic macOS build、临时夹具 smoke、`git diff --check` 和干净工作树。
- 所有 Xcode 构建共用 `.deriveddata-codex`。

## Manual smoke boundary

在签名/公证前用临时夹具副本验证导入、读取、单/批量编辑、保存、reload、rename、renumber、metadata exchange 和失败报告。网络 provider 的 live API 只做用户显式触发的 smoke；确定性 CI 不依赖在线服务。
