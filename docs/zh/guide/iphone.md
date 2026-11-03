# iPhone 与 iPad

RodentLimb 是 App Store 上同一个 App，支持 Mac、iPhone 和 iPad。iPhone 和 iPad 版适合在实验台旁分析少量视频；Mac 版适合大批量长视频。

## 相同之处

- **分析。** 两端编译同一套分析代码：相同的任务、参数、质控、研究设计和导出。同一段视频和关键点得到相同的指标。
- **资料库格式。** 文件夹结构和文件（`Experiments/`、`Recordings/`、`Sessions/`、`pose.bin`）相同。把 iPhone 上的 RodentLimb 文件夹（文件 › 我的 iPhone › RodentLimb）拷贝到 Mac，用 **文件 › 打开资料库…** 打开：研究、视频和结果都在。文件夹里的视频可以直接播放。
- **可见光网络。** iPhone 版以全精度运行这个网络（`CylinderMousePoseV2`）；Mac 版的 CylinderPose7 是同一网络的半精度权重版本，关键点只有舍入级别的差异。见[模型与来源](../models/)。

## Mac 上的不同之处

- 拖放导入整个文件夹，支持命名规则和重复检测。
- 带检查点、自动重试和通宵运行保护的处理队列（[处理队列](./processing.md)）。
- 键盘复核（[快捷键](./shortcuts.md)）、原生表格和检查器。
- 一次导出整个研究或资料库，包括 BORIS、DeepEthogram 和 DeepLabCut 格式（[导出](./export.md)）。
- 近红外模型 PalmReaderPose8。
- 最近删除、自动备份，以及两台 Mac 打开同一资料库时的提醒（[资料库与文件](../reference/files.md)）。

Mac 版不录制视频，也不渲染画有骨架的视频。
