# CylinderPose7（可见光）

<p class="rf-eyebrow">默认模型 · YOLO26s-POSE · 7 个关键点 · FP16</p>

CylinderPose7 在普通室内光视频中跟踪小鼠的爪、鼻尖、嘴和尾根。它是一个 YOLO 姿态模型，从同一实验室圆筒实验录像的几百帧人工标注和两万帧经过仔细清洗的 DeepLabCut 预测中学习，然后以半精度权重导出为 Core ML。

## 模型卡

<table class="rf-kv">
<tr><th>随 App 发布的文件</th><td><code>CylinderPose7_FP16_640.mlpackage</code>（19 MB）；元数据：<em>CylinderMousePose V2 FP16</em>，模型版本 2.1，精度 FP16</td></tr>
<tr><th>与之相同的网络</th><td><code>CylinderMousePoseV2</code>（FP32，38 MB，模型版本 2.0），iPhone 版和 1.3.5 之前的 Mac 版使用</td></tr>
<tr><th>关键点（输出顺序）</th><td><code>L_fore_paw</code>、<code>L_hind_paw</code>、<code>R_fore_paw</code>、<code>R_hind_paw</code>、<code>tail_base</code>、<code>nose</code>、<code>mouth</code>（与实验室 DeepLabCut 项目的顺序相同）</td></tr>
<tr><th>架构</th><td>Ultralytics YOLO26s-pose，从 COCO 预训练的 <code>yolo26s-pose.pt</code> 开始；9,783,360 个参数</td></tr>
<tr><th>输入 / 输出</th><td>640 × 640 RGB 图像 → 原始输出张量 (1, 26, 8400)：4 个框值、1 个小鼠分数、7 × (x, y, 置信度)；模型内不做 NMS</td></tr>
<tr><th>训练数据</th><td>543 帧人工标注（使用两次）+ 来自 506 段录像的 20,000 帧清洗后的 DeepLabCut 伪标签</td></tr>
<tr><th>教师模型</th><td>DeepLabCut ResNet-50 模型 <code>DLC_resnet50_cylinder_DLCJan2shuffle1_44000</code></td></tr>
<tr><th>软件</th><td>Ultralytics 8.4.177、PyTorch 2.11.0、coremltools 9.0</td></tr>
<tr><th>训练运行</th><td><code>20261014_1156_dlc_distill</code>（notebook <code>Cylinder_YOLO26_v2_DLC_Distill</code>）</td></tr>
<tr><th>导出</th><td>Core ML ML Program，<code>quantize=16</code>（FP16 权重），<code>nms=None</code>；2026 年 10 月 14 日</td></tr>
<tr><th>模型包中的许可字段</th><td>AGPL-3.0（导出时由 Ultralytics 写入）</td></tr>
</table>

## 为什么蒸馏 DeepLabCut？

实验室已经有一个 DeepLabCut 模型，并用它跟踪了几百段圆筒实验视频。DeepLabCut 的关键点准确、针对具体项目，但它的 ResNet-50 网络和 Python 环境不适合离线运行的 Mac App。YOLO 姿态模型可以顺利导出为 Core ML。蒸馏把 DeepLabCut 已经跟踪过的视频变成小模型的训练数据。它有两个风险：学生模型可能照搬教师的错误；大量简单、重复的帧可能淹没少见的困难姿势。下面每一步针对其中一个风险。

## 源数据

- **人工标注：** 实验室 DeepLabCut 项目中 38 个 `labeled-data` 文件夹里的 743 帧标注。
- **教师预测：** 每段分析过的视频一条 DeepLabCut 轨迹。把每段录像与其缩小版合并后共有 524 段不同的录像，其中 519 段有上述教师模型的轨迹。视频帧率为 60 fps。
- **可获得性：** 这些录像属于实验室自己的项目。就本页所能确认的情况，它们没有公开发布；如果日后发布（例如作为带 DOI 的数据集），请引用该数据集。

## 第 1 步 · 无泄漏的数据划分

按人工标注的*录像组*划分，因此每个测试帧都是模型从未见过的录像中的人工标注。同一录像的原版和缩小版算作一组。

| 划分 | 人工标注帧 | 录像组 | 用途 |
|---|---|---|---|
| 训练 | 543 | 28 | 训练 |
| 验证 | 120 | 6 | 选择检查点和最终模型 |
| 测试 | 80 | 4 | 只用于报告结果 |

DeepLabCut 伪标签只从验证组和测试组以外的录像中抽取。

## 第 2 步 · 清洗 DeepLabCut 轨迹

每一帧都放在整条轨迹中判断，任何一条规则不满足就丢弃：

| 规则 | 设置 |
|---|---|
| 可见性 | 似然度 ≥ 0.95 → 可见；< 0.50 → 被遮挡；介于两者之间 → 丢弃该帧，避免模型学到错误的“不可见”信号 |
| 足够的点 | 至少 4 个可见点 |
| 时间跳变 | 可见点偏离其 7 帧滚动中位数超过 0.15 个中位体长 |
| 左右互换 | 左右爪都位于尾根→鼻尖轴线上与该视频中通常位置相反的一侧 |
| 几何 | 鼻尖–嘴距离 ≤ 0.35 体长；体长为视频中位数的 0.30–1.60 倍；高置信度的点位于画面内 |

在 34,292,020 帧 DeepLabCut 预测中，这些规则保留了 24,362,080 帧（71.0%）。

## 第 3 步 · 选出 20,000 帧

1. 候选：清洗后的帧，相隔至少 10 帧，每段视频最多 1,500 帧（共 752,692 个候选）。
2. 姿势描述：关键点相对尾根，旋转到身体轴线方向，再除以该视频的中位体长，使站立和四爪着地的姿势保持可区分。
3. 聚类：k-means 分为 60 个姿势簇，另加一组缺少鼻尖或尾根的帧。
4. 均衡抽样：每个簇配额相同，在视频之间轮流抽取，每段视频最多 120 帧。

## 第 4 步 · 对伪标签的独立检查

一个只用人工标注训练的 YOLO 模型（M0）对每个候选帧做预测。只要 M0 对某个点有把握（≥ 0.5），而该点与 DeepLabCut 的位置相差超过 0.25 体长，这一帧就被剔除并列入人工复核清单。M0 处理不了的帧保留，因此这个筛选不会让数据偏向简单姿势。共剔除 903 帧，保留 20,000 个伪标签。

## 第 5 步 · 训练

| 阶段 | 起点 | 训练数据 | 轮数（早停耐心） | 学习率 |
|---|---|---|---|---|
| M0 · 仅人工标注 | `yolo26s-pose.pt` | 543 帧人工标注 | 150（40） | 1e-3 |
| A · 伪标签 + 人工（**发布版**） | `yolo26s-pose.pt` | 20,000 伪标签 + 543 帧人工标注 × 2 | 60（20） | 1e-3 |
| B · 人工微调 | 阶段 A | 543 帧人工标注 | 60（25） | 2e-4 |

共同设置：640 像素、批大小 16、AdamW、余弦学习率、随机种子 42、mosaic 0.5、水平翻转 0.5（同时交换左右关键点）、旋转 ±10°、平移 0.06、缩放 0.25。最终模型按验证帧上的平均关键点误差选择；阶段 A 最低（0.0339 体长）。

## 第 6 步 · 用人工标注评估 {#accuracy}

误差相对人工标注计算，并除以体长（人工标注的鼻尖–尾根距离）。PCK@*t* 是误差在 *t* 体长以内的点所占比例。95% 置信区间来自 2,000 次自助法重抽样。

| 模型（80 个测试帧） | 平均每帧误差 [95% CI] | 中位误差 | 第 90 百分位 | PCK@0.05 | PCK@0.1 |
|---|---|---|---|---|---|
| M0 · 仅人工标注 | 0.0502 [0.040, 0.062] | 4.29 像素 | 12.93 像素 | 0.762 | 0.919 |
| **A · 发布版** | **0.0346 [0.025, 0.046]** | **2.76 像素** | **6.60 像素** | **0.919** | **0.956** |
| B · 人工微调 | 0.0349 [0.026, 0.047] | 3.11 像素 | 6.40 像素 | 0.923 | 0.958 |
| DeepLabCut 教师（参考，60 帧） | 0.0211 [0.018, 0.024] | 2.70 像素 | 5.03 像素 | 0.965 | 0.995 |

每个测试帧都检测到了小鼠。配对差值 A − M0 为 −0.0156 体长 [−0.019, −0.012]：伪标签明显有帮助。约 6% 的测试帧左右爪互换（前爪 6.3%，后爪 6.4%），三个阶段相同。DeepLabCut 教师很可能就是用这些人工标注帧训练的，所以它的数字偏乐观。

## 第 7 步 · 以半精度导出为 Core ML

发布的模型包由阶段 A 的权重通过 Ultralytics 的 Core ML 导出器生成，保留原始姿态输出头，由 App 自己解码：

```python
from ultralytics import YOLO
import coremltools as ct

exported = YOLO('CylinderMousePoseV2.pt').export(
    format='coreml', imgsz=640, quantize=16, nms=None)   # FP16 权重，原始输出 (1, 26, 8400)

m = ct.models.MLModel(exported, skip_model_load=True)    # 只修改元数据
m.short_description = 'CylinderMousePose V2 FP16 - YOLO26s-Pose, DLC distilled, 7 keypoints'
m.version = '2.1'
m.user_defined_metadata.update({'model_family': 'CylinderMousePose', 'model_version': '2.1',
    'precision': 'FP16', 'input_size': '640', 'source_run': '20261014_1156_dlc_distill'})
m.save('CylinderMousePoseV2.mlpackage')
```

之后把模型包改名为 `CylinderPose7_FP16_640.mlpackage`。半精度权重使体积减半（19 MB，原为 38 MB）；104 个权重张量与全精度模型的最大相对差为 0.044%，而且 Mac 的神经网络引擎本来就以半精度计算。

## 局限

- 一个实验室、一套装置、一种相机设置。其他圆筒、光照、帧率或品系未经测试。
- 测试集为 4 个录像组的 80 帧，置信区间相应较宽。
- 约 6% 的测试帧左右爪互换。报告不对称性之前请复核爪的身份。
- 伪标签会继承 DeepLabCut 的系统偏差；一致性筛选只能去掉明显的分歧。
- 模型用圆筒实验视频训练。RodentLimb 也把它用于悬尾、步态、瘙痒、疼痛、理毛和癫痫视频，这些都在训练数据之外。评分前请检查关键点叠加。
- 本页没有报告衍生评分（如触壁次数或抓挠回合）与人工评分的比较。

## 来源

模型包元数据；notebook `Cylinder_YOLO26_v2_DLC_Distill`（训练、评估和 FP16 导出）和 `Cylinder_YOLO26_Pose_Training`（第 1 版，已被取代）；App 源码 `Core/PoseModels.swift`。引用方式：[如何引用](./cite.md#cylinderpose7)。
