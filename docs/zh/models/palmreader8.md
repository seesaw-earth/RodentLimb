# PalmReaderPose8（近红外）

<p class="rf-eyebrow">暗箱模型 · YOLO26s-POSE · 8 个关键点 · 8 位权重</p>

PalmReaderPose8 跟踪在黑暗中、近红外光照明下透过玻璃底板从下方拍摄的小鼠，也就是 *Palmreader* / Blackbox 类平台的录制方式。它是一个 YOLO 姿态模型，用该装置公开的 DeepLabCut 训练集中的人工标注帧训练。

## 模型卡

<table class="rf-kv">
<tr><th>随 App 发布的文件</th><td><code>PalmReaderPose8_640_W8A16.mlpackage</code>（9.8 MB）；元数据：<em>PalmReader mouse pose: 8 keypoints, tailtip excluded</em></td></tr>
<tr><th>关键点（输出顺序）</th><td><code>tailbase</code>、<code>centroid</code>、<code>neck</code>、<code>snout</code>、<code>hlpaw</code>、<code>hrpaw</code>、<code>flpaw</code>、<code>frpaw</code>（左/右后爪、左/右前爪）。源项目的第九个点 <code>tailtip</code>（尾尖）没有参与训练，也不在模型中。</td></tr>
<tr><th>RodentLimb 使用的点</th><td>吻端（存为鼻尖）、尾根和四只爪。身体中心和颈部不保存；没有嘴的关键点。</td></tr>
<tr><th>架构</th><td>Ultralytics YOLO26s-pose，从 COCO 预训练的 <code>yolo26s-pose.pt</code> 开始，输出头改为 8 个关键点；9,834,519 个参数</td></tr>
<tr><th>输入 / 输出</th><td>640 × 640 RGB 图像（等比缩放补边，填充值 114）→ 原始输出张量 (1, 29, 8400)：4 个框值、1 个小鼠分数、8 × (x, y, 置信度)；模型内不做 NMS</td></tr>
<tr><th>训练数据</th><td>Barkai 等（2025）公开的 DeepLabCut 项目中的 409 帧人工标注，Zenodo <a href="https://doi.org/10.5281/zenodo.16321240">10.5281/zenodo.16321240</a>（项目 <code>palmreader-500-AlexZ-2021-03-25</code>）</td></tr>
<tr><th>标签</th><td>只用人工标注。没有使用 DeepLabCut 的预测（伪标签）。</td></tr>
<tr><th>软件</th><td>Ultralytics 8.4.198、PyTorch 2.11.0、coremltools 9.0、NumPy 2.3.5</td></tr>
<tr><th>训练运行</th><td><code>20261102_194842_palm8</code>（notebook <code>PalmReader_YOLO26_8Keypoints_NoTailtip_Colab</code>）；评估与导出运行 <code>20261102_204957_reuse</code>（notebook <code>PalmReader_Pose8_Train_Export_v3_1</code>）</td></tr>
<tr><th>权重校验和</th><td>训练好的 PyTorch 检查点的 SHA-256：<code>88220bb1a9594ccb2e0e99a072f19ec32fcb906cd413f1bb1f6b2b8edbee3d0d</code></td></tr>
<tr><th>导出</th><td>Core ML ML Program，<code>quantize=8</code>：8 位调色板量化权重，半精度（FP16）计算，<code>nms=None</code>；2026 年 11 月 3 日</td></tr>
<tr><th>模型包中的许可字段</th><td>AGPL-3.0（导出时由 Ultralytics 写入）</td></tr>
</table>

## 来源：Palmreader 与 BAREfoot

*Palmreader* 平台在黑暗中用近红外光从下方拍摄自由活动的小鼠，因此既能看到爪与底板的接触，也能看到全身姿态（Zhang 等，2022）。Barkai 等（2025）在这些录像的基础上开发了 *BAREfoot*，一个把 DeepLabCut 姿态估计与基于光强的爪接触测量结合起来、对疼痛行为进行分类的机器学习工具。他们在 Zenodo 上公开了 DeepLabCut 自下而上小鼠跟踪模型及其训练集。

在该研究中，小鼠在玻璃底板下方 30 cm 处由近红外相机以 25 Hz 拍摄，用 850 nm LED 灯带照明；视频以 1000 × 1000 像素录制，分析时缩小到 500 × 500。每只小鼠约 50 帧标注了九个身体部位：吻端、颈部、四只爪、身体中心、尾根和尾尖。

PalmReaderPose8 只重新使用了该训练集中的**人工标注帧**，不包含也不复制 DeepLabCut 网络。

## 第 1 步 · 读取标注

- 标注从项目的 `CollectedData` 文件读取，每个文件夹一位标注者（"scorer"）；不需要项目中原来的 Windows 路径。
- 去掉尾尖，剩下八个点。标注点少于六个的帧和完全重复的帧被跳过（64 帧），剩下 **409 帧**。
- 每个关键点的有效人工标注数：尾根 409、身体中心 409、颈部 332、吻端 385、左后爪 409、右后爪 409、左前爪 376、右前爪 388。缺失的点在训练中被屏蔽，而不是当作已知的遮挡。
- 边界框由可见关键点加边距得到。

## 第 2 步 · 按录像划分

按**录像组**划分，从不按帧划分：原始视频及其缩小版（前缀 `downsized_`、`downsampled_`、`resized_`）算作一组。共找到 15 组。

| 划分 | 帧 | 录像组 |
|---|---|---|
| 训练 | 319 | 11 |
| 验证 | 53 | 2 |
| 测试 | 37 | 2 |

没有图像同时出现在两个划分中（用像素哈希检查）。划分以录像为单位而不是以动物为单位：公开项目没有说明哪些录像来自同一只小鼠，因此同一只动物可能同时出现在训练集和测试集中。

## 第 3 步 · 训练

```python
from ultralytics import YOLO

model = YOLO('yolo26s-pose.pt')                      # COCO 预训练；输出头变为 8 × 3
model.train(data='manual8.yaml', imgsz=640, batch=16, epochs=200, patience=40, seed=42,
            optimizer='AdamW', lr0=1e-3, lrf=0.05, cos_lr=True, deterministic=True,
            mosaic=0.0, mixup=0.0, fliplr=0.0, flipud=0.0,   # 不用 mosaic、mixup 和镜像
            degrees=25, translate=0.1, scale=0.25, hsv_h=0.0, hsv_s=0.0, hsv_v=0.15)
```

关闭镜像增强，因为左右爪必须保持各自的身份。训练在第 108 轮提前停止；最佳检查点（第 68 轮）在验证帧上选出，此时框和姿态的 mAP50 为 0.995，姿态 mAP50-95 为 0.756。测试帧没有用于任何选择。

可选的第二阶段（与 CylinderPose7 一样使用 DeepLabCut 伪标签）没有运行：公开项目中各视频的 DeepLabCut 预测不在训练输入里。因此发布的模型只从人工标注中学习。

## 第 4 步 · 用留出的人工标注评估 {#accuracy}

误差是 37 个测试帧（500 × 500 像素图像）上模型关键点与人工标注之间的像素距离。PCK@*t* 是误差在 *t* 体长以内的标注点所占比例，体长取人工标注的吻端–尾根距离；没有这条轴线的帧（37 帧中的 1 帧）不计入 PCK，缺失或低置信度的预测算作错误。

| 测试集 | 帧 | 标注点 | 检测到小鼠 | 中位误差 | 第 90 百分位 | PCK@0.05 | PCK@0.1 |
|---|---|---|---|---|---|---|---|
| 2 段留出录像 | 37 | 291 | 100% | 9.8 像素 | 24.4 像素 | 0.42 | 0.77 |

在验证帧上，中位误差为 10.4 像素（第 90 百分位 27.3 像素）。在另一段录像（250 × 250 像素，30 fps，14,905 帧）上，99.1% 的帧检测到小鼠，每个关键点在至少 98.8% 的帧中超过 0.35 的置信度阈值；这是跟踪检查，不是准确度指标。

相对动物大小而言，这些误差比 CylinderPose7 大。训练集很小（319 帧），而从下方看爪是很小的目标。从近红外视频得到爪级别的指标时，请仔细检查关键点叠加。

## 第 5 步 · 导出为 Core ML

```python
from ultralytics import YOLO

model = YOLO('PalmReaderPose8.pt')
model.export(format='coreml', imgsz=640, quantize=8, nms=None)   # 8 位权重，FP16 计算，原始输出 (1, 29, 8400)
```

导出时把八个点的名称、输入输出布局和检查点校验和写入模型包元数据，并检查了输出形状。同时也导出了半精度（FP16）版本；RodentLimb 发布的是更小的 8 位权重版本。8 位调色板量化权重减小了体积，计算仍以半精度进行。

::: warning 尚未在设备上验证
模型包元数据记录为 `runtime_verified: false`：Core ML 模型包在 Mac 上的准确度还没有在留出帧上与 PyTorch 模型对比。用于研究之前，请先运行几段近红外视频，在处理队列的实时画面和 QC 播放器中确认关键点落在爪、尾根和吻端上；如果视频条件允许，再与可见光模型比较。
:::

## 局限

- 只有一种装置：黑暗中、玻璃底板上单只小鼠的自下而上近红外视频。其他相机、分辨率、底板材料或光照未经测试。
- 2 段录像的 37 个测试帧；数字的不确定性很大。
- 按录像划分，而不是按动物划分。
- 没有嘴的关键点：需要嘴的任务（舔爪、面部理毛）改用吻端。
- 模型不知道爪的亮度（爪接触力），Palmreader 和 BAREfoot 从同一视频中测量它；RodentLimb 只使用关键点。

## 来源

模型包元数据；notebook `PalmReader_YOLO26_8Keypoints_NoTailtip_Colab`（数据、训练、评估）和 `PalmReader_Pose8_Train_Export_v3_1`（重新评估与 Core ML 导出）；Barkai 等（2025）的方法部分和关键资源表；App 源码 `Core/PoseModels.swift`。引用方式：[如何引用](./cite.md#palmreaderpose8)。
