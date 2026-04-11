# AudioMator 文件格式/元数据支持情况分析（基于源码）

> 分析依据：仅来自仓库源码（未使用 README 结论）。
>
> 主要代码入口：
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/AudioFormatSupport.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/ViewModels/AudioViewModel.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/ViewModels/AudioViewModel+Import.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/ViewModels/AudioViewModel+MetadataWrite.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/Models/AudioFile.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/Models/SingleFileEditModel.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/Models/FileRenameTemplate.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/Models/FilenameMetadataTemplate.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/ViewModels/MusicBrainzTaggingWorkbenchStore.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/Views/Main/InspectorPane.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/TagLibBridge/TagLibMetadataManager.swift`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/TagLibBridge/TagLibMetadataExtractor.h`
> - `/home/runner/work/AudioMator/AudioMator/AudioMator/TagLibBridge/TagLibMetadataExtractor.mm`

---

## 1. 项目级“文件格式支持”总览

项目中的可读/可写/封面写入支持集合来自统一来源：
- `AudioFormatSupport.readableExtensions`
- `AudioFormatSupport.metadataWritableExtensions`
- `AudioFormatSupport.artworkWritableExtensions`

三者当前都等于 `TagLibMetadataExtractor.supportedExtensions()`（全部同一集合）。

### 1.1 支持扩展名（统一集合）

`TagLibMetadataExtractor.supportedExtensions` 定义如下：

- 有损：`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`
- 无损：`flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

### 1.2 功能 × 格式支持（项目层）

| 功能 | 支持范围 | 说明 |
|---|---|---|
| 文件导入（OpenPanel） | 上述全部扩展名 | `AudioViewModel+Import.swift` 使用 `AudioFormatSupport.openPanelContentTypes` |
| 文件夹扫描读取 | 上述全部扩展名 | `AudioViewModel.readableAudioExtensions` |
| 元数据写入（Inspector/批量/导入） | 上述全部扩展名 | `isTagWriteSupportedExtension` 走统一集合 |
| 封面写入（单文件/批量） | 上述全部扩展名 | `isArtworkWriteSupportedExtension` 走统一集合 |
| Raw PropertyMap 编辑写入 | 上述全部扩展名 | `applyRawMetadataPropertyMaps` -> `TagLibMetadataManager.writeRawMetadataPropertyMap` |
| 轨道号重排（Track Renumber） | 上述全部扩展名 | `renumberTrackNumbers` 依赖统一可写集合 |
| “全部清空元数据”入口 | 上述全部扩展名（项目层） | 通过写空字段 + raw map 清空；不是 bridge 的 `wipeMetadataFromURL` |

### 1.3 特殊点

- `TagLibMetadataExtractor.mm` 里有 `wipeMetadataFromURL`，**仅 MP3**，但项目实际清空流程没有用它。
- 项目层“支持写入”不区分容器：统一认为只要在支持扩展列表内都可写。

---

## 2. 项目级“元数据字段支持”总览

## 2.1 AudioFile 读取模型（项目可读取/持有字段）

`AudioFile`（`AudioFile.swift`）持有字段可分为：

- 基础文本：`title`, `artist`, `album`, `composer`, `genre`, `comment`
- 轨道/碟片：`track`, `trackTotal`, `disc`, `discTotal`, `trackNumberText`, `discNumberText`
- 日期与标识：`year`, `releaseDate`, `isrc`, `barcode`
- MusicBrainz：`musicBrainzArtistID`, `musicBrainzAlbumID`, `musicBrainzTrackID`, `musicBrainzReleaseGroupID`
- 版权/发行：`publisher`, `copyright`, `credits`
- 内容分级：`isExplicit`
- 技术：`duration`, `bitrate`, `sampleRate`, `channels`, `format`
- 封面：`artwork`, `artworkFingerprint`

其中：
- 主元数据以 TagLib bridge 为主（`TagLibMetadataManager.readMetadata`）。
- `publisher/copyright/credits` 还会用 AVFoundation 兜底或覆盖。`credits` 当前优先从 AVFoundation `TEXT` 读取。

## 2.2 UI展示字段

- 中间列表列（`MiddleListColumn`）可展示：
  - 文件名、Title/Artist/Album/Album Artist/Composer/Genre/Year
  - Track/Disc（文本优先）
  - Comment/Release Date/Publisher/Copyright/Credits/Explicit
  - Duration/Bitrate/Sample Rate/Channels/Format
- 右侧单文件 Inspector（`InspectorPane.metadataSection`）展示并编辑：
  - Title, Artist, Album, Composer, Genre, Year
  - Track Number（text）, Disc Number（text）
  - Comment, Album Artist, Release Date, Publisher, Copyright
  - Explicit（Bool）
  - Credits 仅显示（不编辑）

## 2.3 项目内“可编辑写回字段”

### 2.3.1 单文件/多文件 Inspector 可编辑

`SingleFileEditModel` + `MultiFileEditableTextField` 当前可编辑写回字段：

- 文本：`title`, `artist`, `album`, `composer`, `genre`, `comment`
- 编号：`trackNumberText`, `discNumberText`
- 日期/归属：`year`, `albumArtist`, `releaseDate`, `publisher`, `copyright`
- 布尔：`isExplicit`
- 封面：replace/remove/unchanged

不可在 Inspector 直接编辑（但可能可读）：
- `isrc`, `barcode`, MusicBrainz IDs, `lyrics`, `sort*`, `mediaType`, `replayGain*` 等。

### 2.3.2 MusicBrainz 批量写回字段

`MusicBrainzTagWriteField` 当前支持：
- `title`, `artist`, `albumArtist`, `album`, `trackNumber`, `discNumber`, `releaseDate`, `publisher`, `composer`

### 2.3.3 文件名提取 -> 元数据写回字段

`FileRenameMetadataField.filenameToMetadataFields` + `supportsFilenameToMetadataWriting`：
- 可写：`title`, `artist`, `album`, `albumArtist`, `composer`, `genre`, `year`, `trackNumberText`, `discNumberText`, `comment`, `releaseDate`, `publisher`, `copyright`
- 不可写：`credits`, `ignore`

### 2.3.4 Raw 元数据编辑窗口

`MetadataEditorWindow` 支持对 TagLib PropertyMap 的任意键值进行增删改（非空键值）。
- 这是唯一直接编辑“任意字段”的项目层功能。
- 最终调用 `TagLibMetadataManager.writeRawMetadataPropertyMap`。

---

## 3. TagLib 桥接层：格式支持分析

桥接核心类：`TagLibMetadataExtractor`（ObjC++）+ `TagLibMetadataManager`（Swift 包装）。

### 3.1 读取（extractMetadataFromURL）按格式分支

- MPEG：`mp3/mp2/aac` -> `TagLib::MPEG::File`，解析 Basic + PropertyMap + ID3v2 + APE + ID3v1兜底
- MP4-like：`m4a/m4b/m4p/mp4` -> `TagLib::MP4::File`，解析 PropertyMap + MP4 ItemMap
- FLAC：`flac` -> `TagLib::FLAC::File`，Xiph + FLAC picture
- Ogg Vorbis：`ogg` -> `TagLib::Ogg::Vorbis::File`，Xiph + complex picture
- Opus：`opus` -> `TagLib::Ogg::Opus::File`，Xiph + complex picture
- Ogg FLAC：`oga` -> `TagLib::Ogg::FLAC::File`，Xiph + complex picture
- APE：`ape` -> `TagLib::APE::File`，APE items
- WavPack：`wv` -> `TagLib::WavPack::File`，APE items
- WAV：`wav` -> `TagLib::RIFF::WAV::File`，PropertyMap + ID3v2
- AIFF：`aiff/aif` -> `TagLib::RIFF::AIFF::File`，PropertyMap + ID3v2
- TrueAudio：`tta` -> `TagLib::TrueAudio::File`，PropertyMap + ID3v2 + ID3v1兜底
- Musepack：`mpc` -> `TagLib::MPC::File`，PropertyMap + APE
- Speex：`spx` -> `TagLib::Ogg::Speex::File`，Xiph + complex picture
- ASF/WMA：`wma/asf` -> `TagLib::ASF::File`，Basic + PropertyMap + complex picture
- DSF：`dsf` -> `TagLib::DSF::File`，PropertyMap + ID3v2（经 tag()）
- DSDIFF：`dff` -> `TagLib::DSDIFF::File`，PropertyMap + ID3v2

如果格式分支未成功打开，会走 `TagLib::FileRef` 兜底读取。

### 3.2 写入（writeMetadata）按格式分支

`writeMetadata` 在 bridge 中支持三大类：
- MPEG-like（`mp3/mp2/aac`）
- MP4-like（`m4a/m4b/m4p/mp4`）
- PropertyMap writable（其余：`flac/ogg/opus/oga/spx/ape/wv/mpc/wav/aiff/aif/tta/wma/asf/dsf/dff`）

因此与项目层一致：支持列表内都可写。

### 3.3 其他写 API

- `writeTrackNumberText`：支持同一整套可写格式（MPEG/MP4/PropertyMap）。
- `writeTrackNumber`：同上（写 track，disc 不在此 API 内）。
- `writeRawPropertyMap`：同上（直接覆盖 property map）。
- `wipeMetadataFromURL`：只实现 MP3（项目主流程未使用）。

---

## 4. TagLib 桥接层：字段支持分析

## 4.1 统一 PropertyMap（跨多格式）字段映射

### 4.1.1 BuildGenericPropertyMap 写出键（核心）

写入键包括（按大类）：
- 基础：`TITLE`, `ARTIST`, `ALBUM`, `COMPOSER`, `GENRE`, `COMMENT`, `ALBUMARTIST`
- 日期：`DATE`, `YEAR`, `ORIGINALDATE`
- 编号：`TRACKNUMBER`, `TRACKTOTAL`, `DISCNUMBER`, `DISCTOTAL`
- 版权与发行：`COPYRIGHT`, `LABEL`, `LYRICS`, `ISRC`, `ENCODEDBY`, `ENCODERSETTINGS`
- 排序：`TITLESORT`, `ARTISTSORT`, `ALBUMSORT`, `ALBUMARTISTSORT`, `COMPOSERSORT`
- 人员/描述：`CONDUCTOR`, `REMIXER`, `PRODUCER`, `ENGINEER`, `LYRICIST`, `SUBTITLE`, `GROUPING`, `MOVEMENT`, `MOOD`, `LANGUAGE`, `INITIALKEY`
- 专业发行：`RELEASETYPE`, `BARCODE`, `CATALOGNUMBER`, `RELEASECOUNTRY`, `MUSICBRAINZ_ARTISTTYPE`
- MBID：`MUSICBRAINZ_ARTISTID`, `MUSICBRAINZ_ALBUMID`, `MUSICBRAINZ_TRACKID`, `MUSICBRAINZ_RELEASEGROUPID`
- ReplayGain：`REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_ALBUM_GAIN`
- 媒体/iTunes：`MEDIATYPE`, `ITUNESALBUMID`, `ITUNESARTISTID`, `ITUNESCATALOGID`, `ITUNESGENREID`, `ITUNESMEDIATYPE`, `ITUNESPURCHASEDATE`, `ITUNNORM`, `ITUNSMPB`
- 其他：`BPM`, `COMPILATION`, `ITUNESADVISORY`
- 自定义：非已知键走 dynamic key 写入

### 4.1.2 ApplyGenericPropertyMapMetadata 读取键（核心）

读取时支持大量同义键，例如：
- `ARTIST/ARTISTS`
- `RELEASEDATE/DATE/YEAR`
- `TRACKNUMBER/TRACK`, `TRACKTOTAL/TOTALTRACKS`
- `DISCNUMBER/DISC`, `DISCTOTAL/TOTALDISCS`
- `INITIALKEY/KEY`
- `BARCODE/UPC/EAN`
- `MEDIATYPE/MEDIA/MEDIA TYPE`
- 显式标记：`ITUNESADVISORY/ADVISORY/EXPLICITCONTENT/EXPLICIT`

并支持将未知键合并为 `customFields`。

## 4.2 ID3v2 专项映射（MPEG/ID3v2 容器）

### 4.2.1 读取

读取帧包括：
- 常规文本帧：`TIT2/TPE1/TALB/TCOM/TCON/TRCK/TPOS/TBPM/TPE2`
- 排序：`TSOT/TSOP/TSOA/TSO2/TSOC`
- 日期：`TDRL/TDRC/TYER/TDOR`
- 人员描述：`TPE3/TPE4/TEXT/TPUB/TENC/TSSE/TSRC/TCOP/TIT3/TIT1/TLAN/TKEY/TMOO/TMED/MVNM/TCMP`
- `COMM` 注释、`USLT` 歌词、`APIC` 封面
- `TXXX` 先走已知映射（`ApplyKnownCustomMetadataField`），否则进自定义字段

### 4.2.2 写入

写入帧包括：
- 基础：`TagLib::Tag` + `TRCK/TPOS`
- 排序/人员/语言/媒体/日期：同上对应帧
- 发行/专业字段：大量 `TXXX`（如 `RELEASETYPE`, `BARCODE`, `CATALOGNUMBER`, `ITUN*`, `RELEASECOUNTRY`, `ARTISTTYPE`, `MusicBrainz *`, `REPLAYGAIN_*`）
- 显式：`TXXX:ITUNESADVISORY`（显式写 `1`，非显式写 `0`）
- 歌词：`USLT`
- 封面：通过 complex properties / APIC 路径
- 自定义字段：非已知 key 作为 `TXXX` 写入

## 4.3 MP4 专项映射

### 4.3.1 读取（ItemMap）

读取 atom/freeform 包括：
- 编号：`trkn`, `disk`
- BPM：`tmpo`
- Album Artist：`aART`
- Composer：`©wrt`
- Compilation：`cpil`
- Explicit：`rtng` + `----:com.apple.iTunes:ITUNESADVISORY`
- 排序：`sonm/soar/soal/soaa/soco`
- Grouping/Copyright/Lyrics/EncodedBy：`©grp/cprt/©lyr/©too`
- 日期：`©day`，原始日期 `----:...:ORIGINAL YEAR`
- 专业字段：`----:...:RELEASETYPE/BARCODE/LABEL/CATALOGNUMBER/MusicBrainz Album Release Country/...`
- 封面：`covr`
- 额外 freeform 会尝试映射到已知字段，否则进 customFields

### 4.3.2 写入（ItemMap）

写入 atom/freeform 包括：
- 基础：`TagLib::Tag` 的 title/artist/album/genre/comment/year/track
- 关键 atom：`aART`, `©wrt`, `©day`, `cprt`, `sonm/soar/soal/soaa/soco`, `©grp`, `©lyr`, `©too`
- 编号：`trkn`, `disk`
- BPM/Compilation/Explicit：`tmpo`, `cpil`, `rtng`
- Explicit 冗余写：`----:...:ITUNESADVISORY`
- 大量 freeform（ISRC、MBID、ReplayGain、iTunes ID 等）
- 内部保真键：
  - `----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT`
  - `----:com.apple.iTunes:AUDIOMATOR_DISCNUMBER_TEXT`
- 封面：`covr` 路径
- 自定义字段：freeform 写入

## 4.4 Xiph / APE / 其他容器

- Xiph（FLAC/Ogg/Opus/Speex/OggFLAC）读取与写入核心都走 PropertyMap，封面走 complex properties（FLAC 另有 picture block 读取）。
- APE（APE/WV/MPC）读取 APE item，写入主要走 PropertyMap + complex picture。
- WAV/AIFF/TTA/DSF/DFF/ASF 等在写入时多走 PropertyMap + 对应 tag 对象处理封面。

## 4.5 自定义字段支持（桥接层）

- 已知字段集合由 `KnownMetadataFieldKeys` 定义。
- 非已知字段：
  - 读取：合并到 `customFields`
  - 写入：
    - ID3v2：写为 `TXXX:<key>`
    - MP4：写为 `----:com.apple.iTunes:<key>`
    - PropertyMap：动态键写入

## 4.6 Raw Metadata 展示与编辑支持

- `rawMetadataForURL`：为支持格式返回 `properties`（MP3 额外 `id3v2Frames`）。
- `dumpMetadataTextFromURL`：输出多段原始视图（PropertyMap、ID3v2、APE、Xiph、RIFF 等）。
- `writeRawPropertyMap`：可对各支持格式直接写入 property map；写前会做规范化并过滤内部隐藏键。

---

## 5. 项目层 vs TagLib桥接层：关键差异总结

1. **格式支持口径基本一致**：项目层所有读写/封面写入都绑定到 `TagLibMetadataExtractor.supportedExtensions`。
2. **项目可编辑字段 < bridge可处理字段**：
   - Inspector 只编辑“常用子集”；
   - Bridge 实际支持大量扩展字段（lyrics/sort/MBID/replaygain/iTunes/freeform/custom）。
3. **“全部清空元数据”实现与 bridge 的 wipe API 不同**：
   - 项目主路径：写空字段 + 清空 raw property map；
   - bridge `wipeMetadataFromURL` 仅 MP3，未作为主流程。
4. **编号文本保真策略**：
   - 项目层使用 `trackNumberText/discNumberText`；
   - bridge 在 MP4 中引入内部 freeform 键保留前导零/原始文本。
5. **Raw 编辑能力最强**：可跨格式直接编辑任意 PropertyMap 键，是项目中覆盖字段最广的功能。

---

## 6. 当前可追踪结论（供多 agent 对齐）

- 项目对格式支持是“统一列表 + 多功能复用”，不存在每个功能独立维护格式白名单（除 `wipeMetadataFromURL` 这种未走主流程 API）。
- 项目元数据能力分三层：
  1) `AudioFile` 可读取层（字段广）
  2) Inspector/批量/导入等业务编辑层（字段中等）
  3) Raw PropertyMap 编辑层（字段最广）
- TagLib bridge 在“跨容器字段兼容、同义键、customFields、封面处理、编号文本保真”方面实现较完整，是当前格式/字段支持的单一事实来源。
