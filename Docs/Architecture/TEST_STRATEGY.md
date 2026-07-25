# Test Strategy

## Fast core tests

命令：`swift test --filter AudioMatorCoreLogicTests`

职责：Foundation-only 的 metadata 语义、track/disc、rename planning、CSV/模板、排序、provider query/ranking、resource limits 和纯 use-case result。测试必须确定性、无网络、无 TagLib、无 UI framework。

属性/模糊测试使用固定 seed、明确迭代次数和输入长度上限。失败输出 seed 与最小必要输入，使 CI 可复现。

## App-hosted tests

命令：

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
```

职责：TagLib adapter、真实 `AudioFile` loading、temporary fixture copies、main-actor state orchestration、mutation serialization、security scope adapter、platform presentation mapping。所有音频写入只使用临时目录中的 fixture 副本。

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
- 最终：目标文件列出的 SwiftPM、强制 build、完整 macOS tests、generic macOS build、generic iOS build、临时夹具 smoke、`git diff --check` 和干净工作树。
- 所有 Xcode 构建共用 `.deriveddata-codex`；不启动 iPad simulator。

## Manual smoke boundary

在签名/公证前用临时夹具副本验证导入、读取、单/批量编辑、保存、reload、rename、renumber、metadata exchange 和失败报告。网络 provider 的 live API 只做用户显式触发的 smoke；确定性 CI 不依赖在线服务。
