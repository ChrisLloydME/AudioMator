# AudioMator 格式与元数据支持说明

本文档描述当前代码状态下 AudioMator 的真实实现口径，重点覆盖：

- 平台差异
- 支持的音频格式
- 可读/可写字段范围
- `Track Number / Total Tracks / Disc Number / Total Discs` 的处理策略
- TagLib 桥接层的设计与当前限制

## 1. 平台支持

### macOS

- 支持 `Current Session`
- 支持 `Watched Folders`
- 主界面为 `sidebar + file list + inspector`
- MusicBrainz、文件名工具、原始元数据编辑器使用独立窗口
- 可显示文件路径并执行 Reveal/Open 一类桌面动作

### iPadOS

- 仅支持 `Current Session`
- 不支持 `Watched Folders`
- 不显示左侧 sidebar
- 主界面为内容区 + Inspector
- 工具页全部改为应用内 sheet
- Inspector 不显示不适合 iPad 的文件路径信息

## 2. 支持格式

当前 TagLib 桥接声明并实际用于导入/读取/写回的扩展名如下：

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

项目层目前将下列能力统一绑定到这组扩展名：

- 导入
- 元数据写入
- Artwork 写入
- Raw property-map 编辑
- Track renumber
- Erase-all metadata

说明：

- 不同容器的字段深度仍然不同。
- “支持写入”表示 AudioMator 会走桥接层写入路径，不代表所有字段在所有容器里都等价。

## 3. 用户层可编辑字段

### Inspector / 批量编辑

当前常规编辑界面支持的主字段包括：

- Title
- Artist
- Album
- Composer
- Genre
- Comment
- Year
- Album Artist
- Release Date
- Publisher
- Copyright
- Explicit
- Track Number
- Total Tracks
- Disc Number
- Total Discs
- Artwork

### 文件名工具

`Metadata -> Filename` 与 `Filename -> Metadata` 现在都能处理拆分后的编号字段逻辑，并与主编辑模型共享同一套数值语义。

### MusicBrainz

MusicBrainz 写回流程支持将远端编号信息映射到本地：

- Track Number
- Total Tracks
- Disc Number
- Total Discs

同时仍支持标题、演出者、专辑、发行日期、Publisher、Composer 等字段。

### Raw Metadata Editor

Raw Metadata Editor 仍然是覆盖面最广的编辑入口，可以直接增删改任意 property-map 键值。

## 4. Track / Disc 四字段支持策略

这是当前桥接层里最重要的一组字段。

### 4.1 统一数据模型

项目内部现在将四个字段分开建模：

- `track`
- `trackTotal`
- `disc`
- `discTotal`

同时保留两份文本表示：

- `trackNumberText`
- `discNumberText`

文本表示用于保留：

- 前导零
- 容器已有格式
- 用户显式输入的 `01/10`、`1/10`、`03` 这类展示语义

### 4.2 UI 层行为

- 单文件 Inspector 直接编辑四个字段
- 多文件编辑支持分别批量写入四个字段
- 文件名模板导入/导出走同一套 number-pair 逻辑
- MusicBrainz 写回不再只传入模糊的合并文本

### 4.3 写入策略

#### ID3v2 / MPEG

- 写 `TRCK`
- 写 `TPOS`
- 在只改曲号、不改总数时保留已有 total
- 在可表示的情况下保留文本格式

#### PropertyMap 类格式

- 写 `TRACKNUMBER`
- 写 `TRACKTOTAL`
- 写 `DISCNUMBER`
- 写 `DISCTOTAL`
- 同时兼容 `TOTALTRACKS` / `TOTALDISCS` 这类别名读取

#### MP4 / M4A

- 写标准 `trkn`
- 写标准 `disk`
- 额外写内部 freeform 文本键保存显示格式
  - `AUDIOMATOR_TRACKNUMBER_TEXT`
  - `AUDIOMATOR_DISCNUMBER_TEXT`

这样做的原因：

- `trkn` / `disk` 负责标准数值语义
- 自定义文本键负责保留 `02/09` 这样的零填充显示

### 4.4 读回与校验

写入后，桥接层会校验：

- 数值是否一致
- 文本是否等价
- 是否只是容器归一化了格式

例如：

- `02/09 -> 2/9` 可被识别为“格式被容器规范化”
- `02/09 -> 2/0` 会被识别为真实异常

## 5. 本轮桥接层修复与验证

本轮针对真实音频样本修复并验证了一个 MP4/M4A 的关键问题。

### 问题

在 MP4 的 `writeTrackNumberText` 路径中，代码先写入 `trkn(number,total)`，随后又调用 `setTrack(number)`，把刚写进去的 `total` 覆盖回了 `0`。

外在表现是：

- `trackText` 读回是 `02/09`
- 但 `totalTracks` 却读回成 `0`

### 修复

已调整写入顺序，避免 `setTrack()` 覆盖 `trkn` 的总曲数。

### 实测结果

使用 `.tmp` 内的真实 `m4a` 样本回归后：

- `02/09` 现在能正确读回 `track = 2, totalTracks = 9, trackText = 02/09`
- 只写 `03` 时，已有 `totalTracks = 9` 可以保留
- 显式写 `07/12` 与 `2/3` 时，曲目与碟片总数都能一起正确更新

### 新增回归工具

仓库新增：

- `scripts/build-taglib-bridge-smoke.sh`
- `scripts/taglib_bridge_smoke.mm`

用途：

- 读取标准化元数据
- 查看 raw property map
- 单独验证 track/disc 文本写回
- 做整条桥接写入 roundtrip

## 6. TagLib 桥接层当前设计

### Swift 层

- `TagLibMetadataManager.swift`
- 负责 Swift 侧读写包装、回读校验、warning 归因、property-map dump 组织

### Objective-C++ 层

- `TagLibMetadataExtractor.mm`
- 负责实际容器分支处理、TagLib API 调用、格式细节与 artwork/number 专项逻辑

### 当前设计重点

- 尽量以统一 `BasicMetadata` / `TagLibAudioMetadata` 模型贯穿 UI 和桥接
- 对于编号字段，同时维护“数值语义”和“显示文本”
- 对 MP4 使用标准 atom + 内部 freeform 双轨保真
- 对 property-map 风格容器优先保持兼容性，而不是强行抽象成单一容器行为

## 7. 仍然存在的现实约束

- 不同容器对 number formatting 的保真度不同
- 有些容器的 property-map 会自动规范化大小写或显示格式
- `Erase All Metadata` 仍是 best-effort 语义，不保证所有容器都能做到完全一致的“空白状态”
- iPadOS 由于沙盒限制，不会补做桌面式文件夹监听模型

## 8. 建议的开发回归命令

```bash
bash scripts/codex-build.sh
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke write-roundtrip .tmp/sample.m4a
./.tmp/taglib_bridge_smoke write-track .tmp/sample.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke raw .tmp/sample.m4a
```
