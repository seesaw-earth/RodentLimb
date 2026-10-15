# 开源与构建

RodentLimb 以 **[GNU AGPL-3.0](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)** 开源。App、所有分析代码和本手册都在同一个公开仓库中：

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## 代码位置

| 主题 | 手册页面 | 源文件 |
|---|---|---|
| 姿态推理、解码、读取视频 | [姿态模型](./principles/pose.md) | [`PoseEngine.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Pose/PoseEngine.swift)、[`PoseDecoder.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Pose/PoseDecoder.swift) |
| 预处理、体长、信号工具 | [姿态模型](./principles/pose.md#预处理) | [`PoseSeries.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/PoseSeries.swift) |
| 悬尾实验 | [悬尾实验](./assays/tail-suspension.md) | [`TSTAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/TSTAnalyzer.swift) |
| 圆筒实验 | [圆筒实验](./assays/cylinder.md) | [`CylinderAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/CylinderAnalyzer.swift) |
| 步态分析 | [步态分析](./assays/gait.md) | [`GaitAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/GaitAnalyzer.swift) |
| 参数与默认值 | [参数](./guide/parameters.md) | [`AnalysisModels.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/AnalysisModels.swift) |
| 导出与方法描述 | [文件与导出](./reference/files.md) | [`Exporter.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Data/Exporter.swift) |
| 验证脚本 | [验证](./principles/validation.md) | [`Tools/validation/`](https://github.com/seesaw-earth/RodentLimb/tree/main/Tools/validation) |
| 中英文文本 | — | 各界面中的 `L("English", "中文")`；[`L10n.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/App/L10n.swift) |

## 从源代码构建

需要装有 **Xcode 16 或更高版本**的 Mac，以及 **iOS 17 或更高版本**的 iPhone。没有第三方 Swift 包依赖。

```bash
git clone https://github.com/seesaw-earth/RodentLimb.git
cd RodentLimb
python3 Tools/install_model.py --v2 /path/to/CylinderMousePoseV2.mlpackage.zip
open RodentLimb.xcodeproj
```

在 Xcode 中选择签名团队，然后在 iPhone 上运行。模型权重**不在**仓库中，见 `MODEL_PROVENANCE.md`。

## 构建本手册

```bash
npm install
npm run docs:dev     # 本地预览 http://localhost:5173/RodentLimb/
npm run docs:build   # 静态网站输出到 docs/.vitepress/dist
```

把 `docs/` 下的修改推送到 `main` 分支后，GitHub Actions 会自动发布网站。
