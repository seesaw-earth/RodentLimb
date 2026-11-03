---
outline: [2, 2]
---

# 法律与声明

## 许可

RodentLimb 的源代码以 **GNU Affero 通用公共许可证 v3.0** 发布（[LICENSE](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)）。你可以在该许可的条款下使用、研究、修改和分享它。App 在 App Store 上免费提供；你对 App Store 版本的使用同时受 Apple 的[许可应用程序最终用户许可协议](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)约束。

© 2026 Ziqing Shi。

## 姿态模型

姿态模型用 [Ultralytics YOLO](https://github.com/ultralytics/ultralytics) 训练和导出，后者以 AGPL-3.0 或 Ultralytics 企业许可提供。模型文件不在源代码仓库中；其来源、训练数据和许可见模型页面：

- [CylinderPose7](./models/cylinderpose7.md)——用标注的圆筒实验帧训练，并从 DeepLabCut 模型蒸馏。
- [PalmReaderPose8](./models/palmreader8.md)——用 Barkai 等（2025）公开的 DeepLabCut 训练集中的人工标注帧训练，Zenodo 记录 [10.5281/zenodo.16321240](https://doi.org/10.5281/zenodo.16321240)。如果使用该模型，也请引用这项工作；见[如何引用](./models/cite.md)。

## 第三方软件

| 组件 | 用途 | 许可 |
|---|---|---|
| Apple 系统框架（SwiftUI、Swift Charts、Core ML、Vision、AVFoundation） | App | Apple 开发者条款 |
| Ultralytics YOLO | 训练和导出姿态模型 | AGPL-3.0 |
| coremltools | 把模型转换为 Core ML | BSD-3-Clause |
| DeepLabCut | 训练数据背后的标注项目 | LGPL-3.0 |
| VitePress | 本网站 | MIT |

App 不使用第三方 Swift 包、统计分析或广告 SDK。

## 仅供研究使用

RodentLimb 是用于实验动物研究的工具。它不是医疗器械，不用于人类或动物的诊断或治疗。

结果由关键点自动计算，取决于你的视频、姿态模型和你选择的参数。依赖结果之前，请在你自己的装置上与人工评分比较（见[验证](./principles/validation.md)）。本软件**按“原样”提供，不附带任何形式的担保**，详见 AGPL-3.0 第 15 和第 16 条。

## 动物研究

RodentLimb 分析视频；它不能替代适用于你的工作的审批、伦理审查和福利标准。请遵守所在机构的动物管理和使用要求，并按 [ARRIVE 2.0](https://arriveguidelines.org/) 指南报告实验。

## 商标

Apple、Mac、macOS、iPhone、iPad、App Store 和 Core ML 是 Apple Inc. 的商标。其他产品名称归其各自所有者所有。RodentLimb 与 Apple、Ultralytics 或 DeepLabCut 项目没有关联，也未获得其认可。

## 联系

[github.com/seesaw-earth/RodentLimb/issues](https://github.com/seesaw-earth/RodentLimb/issues) · [支持](./support.md) · [隐私政策](./privacy.md)
