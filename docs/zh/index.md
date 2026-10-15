---
layout: home
title: RodentLimb
titleTemplate: 使用手册

hero:
  name: RodentLimb
  text: 在 iPhone 上完成肢体姿态与运动行为分析
  tagline: 逐帧识别四只爪、鼻尖和尾根，完成悬尾、圆筒和步态实验的分析。全部在手机上运行，不上传任何数据。
  image:
    src: /hero.png
    alt: RodentLimb 图标
  actions:
    - theme: brand
      text: 快速上手
      link: /zh/guide/getting-started
    - theme: alt
      text: 实验范式
      link: /zh/assays/
    - theme: alt
      text: GitHub 源代码
      link: https://github.com/seesaw-earth/RodentLimb
    - theme: alt
      text: English
      link: /

features:
  - title: 七个关键点，逐帧识别
    details: 基于小鼠视频训练的姿态模型，在 iPhone 本机上逐帧找出四只爪、尾根、鼻尖和嘴。
    link: /zh/principles/pose
    linkText: 姿态模型
  - title: 悬尾实验
    details: 不动时间与比例、潜伏期、不动次数、逐分钟曲线、爬尾比例，以及后肢抱握的估计评分。
    link: /zh/assays/tail-suspension
    linkText: 悬尾实验
  - title: 圆筒实验
    details: 竖立时左爪、右爪、双爪触壁，以及相对损伤侧的不对称指标。每一次触壁都可以回放并修改标签。
    link: /zh/assays/cylinder
    linkText: 圆筒实验
  - title: 步态分析
    details: 支撑相、摆动相、步幅、占空比、支撑面宽度、肢间相位、步态模式与全身摆动，并给出共同参考速度下的速度匹配值。
    link: /zh/assays/gait
    linkText: 步态分析
  - title: 改参数，结果即时更新
    details: 每段视频只运行一次模型。阈值、分析窗口和标定都可以事后修改，结果立即重算。
    link: /zh/guide/parameters
    linkText: 参数
  - title: 隐私与开源
    details: 无需账号，无统计分析，不联网。导出为英文，附带可直接引用的方法描述。源代码公开。
    link: /zh/source
    linkText: 源代码
---

<div class="rf-home">

<p class="rf-lang">语言：<a href="../index.html">English</a> · <a href="./index.html">简体中文</a></p>

## 工作流程

模型对每段视频只读取一次，并保存关键点。之后的预处理、范式分析和结果都很快，每次修改参数或标签时都会重新计算。

<figure>

![从视频到结果](/img/pipeline.zh.svg)

</figure>

## 实验范式

| 范式 | 主要指标 | 拍摄方式 |
|---|---|---|
| [悬尾实验](./assays/tail-suspension.md) | 不动时间（秒、%）、潜伏期、不动次数、抱握评分、爬尾 | 悬挂小鼠的正面或背面 |
| [圆筒实验](./assays/cylinder.md) | 左爪 / 右爪 / 双爪触壁、对侧使用率、不对称指数 | 透明底面下方仰拍（或侧拍） |
| [步态分析](./assays/gait.md) | 步幅、支撑相、摆动相、占空比、支撑面宽度、相位、步态模式、摆动 | 透明步道下方仰拍，≥ 60 fps |

## 开源

RodentLimb 以 GNU AGPL-3.0 开源。分析代码、每个指标的定义和本手册都在同一个公开仓库中，你可以确切地看到每个数字是如何算出来的。

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## 从这里开始

<div class="rf-cards">
  <a href="./guide/getting-started.html"><strong>快速上手</strong><span>几分钟内从一段视频得到第一个结果。</span></a>
  <a href="./guide/recording.html"><strong>拍摄要点</strong><span>相机位置、光线和帧率，让爪的识别更可靠。</span></a>
  <a href="./assays/index.html"><strong>范式说明</strong><span>每个范式测什么，每个数值如何定义。</span></a>
  <a href="./principles/validation.html"><strong>验证</strong><span>哪些已与真值对照验证，哪些需要你自己核对。</span></a>
</div>

</div>
