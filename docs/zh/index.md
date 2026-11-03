---
layout: home
title: RodentLimb
titleTemplate: 小鼠视频的肢体姿态与行为评分

hero:
  name: RodentLimb
  text: 在 Mac 上完成小鼠视频的肢体姿态与行为评分
  tagline: 在长视频的每一帧中识别四只爪、鼻尖、嘴和尾根，然后完成七项实验的评分：从悬尾、步态到瘙痒、疼痛、理毛和癫痫。全部在 Mac 本机运行，不上传任何数据。
  image:
    src: /hero.png
    alt: RodentLimb 图标
  actions:
    - theme: brand
      text: Mac App Store
      link: https://apps.apple.com/app/id6822935387
    - theme: alt
      text: 快速上手
      link: /zh/guide/getting-started
    - theme: alt
      text: 姿态模型与来源
      link: /zh/models/
    - theme: alt
      text: English
      link: /

features:
  - title: 两个姿态模型，按光照选择
    details: CylinderPose7 用于普通室内光视频，PalmReaderPose8 用于暗箱中从下方拍摄的近红外视频。两者都通过 Core ML 在 Mac 上运行。
    link: /zh/models/
    linkText: 模型与来源
  - title: 一套流程，七项实验
    details: 悬尾、圆筒、步态、瘙痒、自发痛行为、自我理毛和癫痫发作评分。每个事件都可以在视频上回放并修改标签。
    link: /zh/assays/
    linkText: 实验任务
  - title: 为通宵批处理而设计
    details: 把一整个文件夹的视频拖进来。队列逐帧识别并写入检查点，暂停、崩溃或断电只损失几秒，而不是几小时。
    link: /zh/guide/processing
    linkText: 处理队列
  - title: 先质控，再评分
    details: 每个研究在分析前设定纳入标准。每段视频得到通过、需检查或不通过的结论，每次排除都保留原因。
    link: /zh/guide/qc
    linkText: 质量控制
  - title: 研究设计、盲法与规范导出
    details: 因素、时间点、随机分组和盲法。每个任务一张长格式表，一张行为片段表，一段方法学文字，以及 BORIS / DeepLabCut 格式。
    link: /zh/guide/export
    linkText: 导出
  - title: 隐私优先
    details: 无需账号，不联网，无统计分析。视频保留在原处，只读取不修改。支持英文和简体中文。
    link: /zh/privacy
    linkText: 隐私政策
---

<div class="rf-home">

## 工作流程

1. **导入。** 把视频或整个文件夹拖进窗口。动物编号、时间点和试次从文件名读出；按光照条件选择姿态模型。
2. **识别。** 姿态模型在后台队列中把每一帧读一遍，并保存关键点。
3. **检查。** 每段视频按研究设定的标准得到质控结论；其余视频由你纳入或排除，并写明原因。
4. **评分。** 分配一个或多个任务。修改参数时结果立即更新，因为模型不需要再运行。
5. **复核与导出。** 在视频上回放每个检测到的事件，修正标签，然后为整个研究导出数据表、行为片段和方法学文字。

## 姿态模型

| 模型 | 适用视频 | 使用的关键点 | 训练数据 |
|---|---|---|---|
| [**CylinderPose7**（默认）](./models/cylinderpose7.md) | 普通室内光，通常从透明底板下方拍摄 | 四爪、尾根、鼻尖、嘴 | 一个实验室的圆筒实验录像：543 帧人工标注 + 20,000 帧清洗后的 DeepLabCut 预测 |
| [**PalmReaderPose8**](./models/palmreader8.md) | 黑暗中从下方拍摄、近红外光照明（暗箱装置） | 四爪、尾根、吻端（存为鼻尖） | Barkai 等（2025）公开的 DeepLabCut 训练集中 409 帧人工标注 |

两者都是输入 640 像素的 Ultralytics YOLO26s-pose 网络，导出为 Core ML。数据来源、训练与测试方法以及引用方式见[模型与来源](./models/)。

## 实验任务

| 任务 | 主要指标 |
|---|---|
| [悬尾实验](./assays/tail-suspension.md) | 不动时间与百分比、潜伏期、不动回合、逐分钟曲线、爬尾、估计的后肢抱握评分 |
| [圆筒实验](./assays/cylinder.md) | 左爪、右爪和双爪触壁次数，对侧使用率，不对称指数 |
| [步态分析](./assays/gait.md) | 步幅、支撑相、摆动相、占空比、支撑基宽、肢间相位、步态模式、速度匹配值 |
| [瘙痒（抓挠）](./assays/itch.md) | 致痒剂注射后的抓挠回合、时间、潜伏期和抓挠串，哪只后爪，时间进程 |
| [自发痛行为](./assays/pain.md) | 注射爪的舔咬和缩爪/甩爪，福尔马林 I / II 相，时间进程 |
| [自我理毛](./assays/grooming.md) | 理毛时间、回合、潜伏期、身体部位、中断回合与错误转换 |
| [癫痫发作评分](./assays/seizure.md) | 肌阵挛抽动、阵挛和强直-阵挛发作、潜伏期、估计的 Racine 分级 |

## 适合谁

在标准行为实验中拍摄小鼠、希望得到关键点级别的指标，又不想写代码或把视频发到别处的实验室。RodentLimb 给出数字、背后的事件和方法学文字；它不能代替人工抽查一部分视频。见[验证与局限](./principles/validation.md)。

## Mac、iPhone 与 iPad

RodentLimb for Mac 为大批量长视频设计。iPhone 和 iPad 版使用同一套分析代码和同样的资料库格式，资料库可以在设备之间拷贝，在任一端打开。见 [iPhone 与 iPad](./guide/iphone.md)。

## 引用

如果 RodentLimb 对发表的工作有贡献，请引用 App 及其版本，以及所用姿态模型的数据和软件。具体文献见[如何引用](./models/cite.md)。

</div>
