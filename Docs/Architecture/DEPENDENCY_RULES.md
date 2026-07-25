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
- `Domain` 可以依赖 Foundation 和项目内纯逻辑 Core；不得依赖 SwiftUI、AppKit、UIKit、Combine、TagLib 或具体网络 client，除非文档记录了无法隔离的理由。
- `Infrastructure` 实现 Domain contract，拥有 TagLib、文件系统、bookmark、directory monitor、URLSession/provider DTO、更新服务和系统 adapter。
- provider-specific query/DTO/matching 可以留在对应 Infrastructure 目录；跨 provider 抽象必须由至少两条稳定、相同的业务语义证明。

## Platform boundaries

- macOS/iPadOS 分支优先位于 App、Features 或 `Core/Platform` adapter。
- 同一 metadata、rename、exchange 或 renumber 规则不得因平台条件编译而复制。
- iPadOS 不引入 watched-folder 持久化；macOS 不被迫采用 session-only 文件模型。

## Mutation boundaries

- UI 只能提交显式 mutation input 并消费结果，不得直接写 TagLib 或移动文件。
- 所有磁盘 mutation 必须通过共享的路径 reservation。
- 成功写入后的 reload 属于同一 mutation ownership 范围；UI snapshot replacement 在主 actor 上发生。
- 对外结果必须区分：未写入、已写入且刷新成功、已写入但刷新失败、部分批次失败、取消、需要人工恢复。

## Enforcement

- SwiftPM `AudioMatorCoreLogic` source list 是纯逻辑快速传感器，不得加入 AppKit、UIKit、SwiftUI、Combine、TagLib 或网络依赖。
- app-hosted tests 覆盖 adapter、真实 `AudioFile`、TagLib、文件系统与主 actor 编排。
- 每次新跨层 import、公开 protocol 或 service 都必须说明调用方、被替代耦合和独立测试收益。
