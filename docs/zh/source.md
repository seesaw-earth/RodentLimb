# 开源与构建

RodentLimb 以 **[GNU AGPL-3.0](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)** 开源。App、分析代码和本手册都在同一个公开仓库中：

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## 代码的组织方式

iPhone 版和 Mac 版共用一层分析代码，因此同一段视频在两端得到相同的关键点和相同的指标。

| 部分 | 作用 |
|---|---|
| **共享分析层** | 关键点预处理、七个分析器、质控、研究设计、导出和方法学文字。只依赖 Foundation，因此也能在命令行编译和测试 |
| **iPhone 版** | 在手机上录制和导入、Core ML 识别、iPhone 界面 |
| **Mac 版** | 资料库、带检查点的批处理引擎、Core ML + Vision 识别、Mac 界面 |
| **姿态模型** | 不在仓库中（见[姿态模型](./models/)）；用 `install_model.py` 安装到工程中 |
| **本手册** | `docs/` 中的 VitePress 网站，通过 GitHub Pages 发布 |

## 代码中的对应位置

| 主题 | 手册页面 | 源文件 |
|---|---|---|
| 姿态推理与解码 | [姿态模型与预处理](./principles/pose.md) | `PoseRunner.swift`（Mac）、`PoseEngine.swift`（iPhone）、`PoseDecoder.swift` |
| 预处理、缺口填补、体长 | [姿态模型与预处理](./principles/pose.md#预处理) | `PoseSeries.swift`、`GapRepair.swift` |
| 悬尾实验 | [悬尾实验](./assays/tail-suspension.md) | `TSTAnalyzer.swift` |
| 圆筒实验 | [圆筒实验](./assays/cylinder.md) | `CylinderAnalyzer.swift` |
| 步态分析 | [步态分析](./assays/gait.md) | `GaitAnalyzer.swift` |
| 瘙痒 | [瘙痒](./assays/itch.md) | `ItchAnalyzer.swift`、`ScratchModel.swift` |
| 自发痛行为 | [自发痛行为](./assays/pain.md) | `PainAnalyzer.swift` |
| 自我理毛 | [自我理毛](./assays/grooming.md) | `GroomingAnalyzer.swift` |
| 癫痫发作评分 | [癫痫发作评分](./assays/seizure.md) | `SeizureAnalyzer.swift` |
| 质量控制 | [质量控制](./guide/qc.md) | `QualityControl.swift` |
| 参数、默认值、预设 | [参数](./guide/parameters.md) | `AnalysisModels.swift`、`ParameterPresets.swift` |
| 导出与方法学文字 | [导出](./guide/export.md) | `Exporter.swift`、`StudyExport.swift` |
| 验证脚本 | [验证](./principles/validation.md) | [`Tools/validation/`](https://github.com/seesaw-earth/RodentLimb/tree/main/Tools/validation) |
| 中英文文字 | — | 每个界面中的 `L("English", "中文")` 调用；`L10n.swift` |

::: info 仓库中的版本
仓库正在更新为两个 App 的 1.3.5 源代码。在完成之前，其中可能还是较早的版本；各版本的更新说明见[更新说明](./reference/changelog.md)。
:::

## 从源代码构建

需要 **Xcode 16 或更新版本**。没有第三方 Swift 包。

- **Mac**：macOS 14 或更新版本。打开 Mac 工程，选择签名团队后运行。工程使用同步文件夹，新文件会自动加入。
- **iPhone**：iOS 17 或更新版本的 iPhone 或 iPad。

模型权重不在仓库中。构建前请先安装到工程中，例如：

```bash
python3 tools/install_model.py --fp16 /path/to/CylinderPose7_FP16_640.mlpackage.zip   # 可见光
python3 tools/install_model.py --nir  /path/to/PalmReaderPose8_640_W8A16.mlpackage.zip # 近红外
```

权重的来源和训练方法见[模型页面](./models/)。

## 构建本手册

```bash
npm install
npm run docs:dev     # 实时预览：http://localhost:5173/RodentLimb/
npm run docs:build   # 静态网站输出到 docs/.vitepress/dist
```

把 `docs/` 下的修改推送到 `main` 后，GitHub Actions 会自动发布网站。
