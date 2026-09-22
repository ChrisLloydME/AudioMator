# Dependency Rules

## Allowed direction

```text
App composition
  └─ Features / application use cases
       ├─ Domain contracts and values
       └─ injected Infrastructure adapters

Infrastructure adapters
  └─ Domain contracts and values
```

- `App` 可以依赖所有层，但只负责装配、命令、生命周期和平台入口。
- `Features` 可以依赖 Domain contract/value 与平台 UI framework；不得直接调用 TagLib 容器 API或实现文件事务。
- `Domain` 可以依赖 Foundation 和项目内纯逻辑 Core；不得依赖 SwiftUI、AppKit、Combine、具体网络 client 或 TagLib 容器/文件 API。Metadata boundary 当前有一个记录在 ADR 0003 的例外：复用 `TagLibAudioMetadata` 的 `MetadataFieldKey`、`MetadataFileVersion` 和 `RawMetadataPatch` 语义类型，以保持字段能力、revision 与精确 delta 的单一 contract。具体 manager、snapshot extraction、container conversion 和 transaction implementation 仍只属于 Infrastructure。
- `Infrastructure` 实现 Domain contract，拥有 TagLib、文件系统、bookmark、directory monitor、URLSession/provider DTO、更新服务和系统 adapter。
- provider-specific query/DTO/matching 可以留在对应 Infrastructure 目录；跨 provider 抽象必须由至少两条稳定、相同的业务语义证明。

## Platform boundaries

- AppKit integration belongs in App, Features, Infrastructure, or a focused `Core/Platform` adapter rather than Domain logic.
- Metadata, rename, exchange, and renumber rules must remain independent of UI framework code.

## Mutation boundaries

- UI 只能提交显式 mutation input 并消费结果，不得直接写 TagLib 或移动文件。
- 所有磁盘 mutation 必须通过共享的路径 reservation。
- semantic mutation 必须按 requested field 做 format-capability preflight；不能只检查 extension 是否 broadly writable。低层 raw editor 是明确例外。
- 成功写入后的 reload 属于同一 mutation ownership 范围；UI snapshot replacement 在主 actor 上发生。
- rename 后若完整 reload 失败，必须恢复 fingerprint 与 metadata revision；无法恢复时 snapshot 标记为 refresh-required，并禁止未受保护的后续写入。
- 对外结果必须区分：未写入、已写入且刷新成功、已写入但刷新失败、部分批次失败、取消、需要人工恢复。

## Enforcement

- SwiftPM `AudioMatorCoreLogic` source list 是纯逻辑快速传感器，不得加入 AppKit、SwiftUI、Combine、TagLib 或网络依赖。
- app-hosted tests 覆盖 adapter、真实 `AudioFile`、TagLib、文件系统与主 actor 编排。
- 每次新跨层 import、公开 protocol 或 service 都必须说明调用方、被替代耦合和独立测试收益。
- `AudioFile` 可以保存由 `Core/Platform` 定义的原生 artwork snapshot，以避免在每个 inspector binding 中重复解码；TagLib、AVFoundation 与 AppKit 的构造行为必须留在 Infrastructure adapter。
