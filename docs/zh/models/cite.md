# 如何引用

如果 RodentLimb 对发表的工作有贡献，请引用 App 及所用版本、姿态模型的软件，以及模型的训练数据。RodentLimb 导出的方法学段落已经写明模型、参数和任务的参考文献；请把下面的文献加入你的参考文献列表。

## RodentLimb

> Shi, Z. (2026). *RodentLimb* (Version [所用版本]) [Computer software]. https://seesaw-earth.github.io/RodentLimb/

```bibtex
@software{shi2026rodentlimb,
  author  = {Shi, Ziqing},
  title   = {RodentLimb: limb pose and behavior scoring for mouse videos},
  version = {1.3.5},
  year    = {2026},
  url     = {https://seesaw-earth.github.io/RodentLimb/}
}
```

把版本号换成 **RodentLimb › 关于 RodentLimb** 中显示的版本。导出清单（`export_manifest.json`）记录了 App 版本和每段视频所用的模型。

## 如果使用了 CylinderPose7（可见光） {#cylinderpose7}

| 引用 | 原因 |
|---|---|
| RodentLimb 及版本 | 运行模型并计算你的指标 |
| Ultralytics YOLO26（Jocher 等，2026） | 网络架构、预训练权重、训练和导出代码 |
| DeepLabCut（Mathis 等，2018；Nath 等，2019） | 生成 20,000 个训练标签的教师模型 |
| COCO（Lin 等，2014），建议引用 | 初始权重在 COCO 关键点上预训练 |
| 该实验室的圆筒实验录像 | 训练数据；如果已作为数据集发表，请引用该数据集 |

方法学示例（英文论文可直接使用）：*Pose was estimated on every frame with CylinderPose7 (CylinderMousePose v2.1, a YOLO26s-pose network distilled from a DeepLabCut model, half-precision Core ML; seven keypoints: four paws, tail base, nose and mouth) in RodentLimb [version] on macOS.*

中文示例：*用 RodentLimb [版本]（macOS）中的 CylinderPose7（CylinderMousePose v2.1，由 DeepLabCut 模型蒸馏得到的 YOLO26s-pose 网络，半精度 Core ML；七个关键点：四爪、尾根、鼻尖和嘴）逐帧估计姿态。*

## 如果使用了 PalmReaderPose8（近红外） {#palmreaderpose8}

| 引用 | 原因 |
|---|---|
| RodentLimb 及版本 | 运行模型并计算你的指标 |
| Ultralytics YOLO26（Jocher 等，2026） | 网络架构、预训练权重、训练和导出代码 |
| Barkai 等（2025）及 Zenodo 记录 10.5281/zenodo.16321240 | 人工标注的训练帧来自他们公开的 DeepLabCut 训练集 |
| Zhang 等（2022） | 自下而上的近红外录制平台（Palmreader） |
| DeepLabCut（Mathis 等，2018） | 标注是在 DeepLabCut 项目中完成的 |
| COCO（Lin 等，2014），建议引用 | 初始权重的预训练 |

方法学示例：*Pose was estimated on every frame with PalmReaderPose8 (a YOLO26s-pose network trained on the human-labelled frames of the bottom-up near-infrared DeepLabCut training set of Barkai et al., 2025; 8-bit Core ML) in RodentLimb [version] on macOS; its snout, tail base and four paw keypoints were used.*

中文示例：*用 RodentLimb [版本]（macOS）中的 PalmReaderPose8（用 Barkai 等（2025）自下而上近红外 DeepLabCut 训练集的人工标注帧训练的 YOLO26s-pose 网络，8 位 Core ML）逐帧估计姿态，使用其吻端、尾根和四爪关键点。*

## 如果报告某个任务

每个任务页面列出了其指标背后的方法学文献，导出的 `*_methods.txt` 也包含这些文献和你的参数值。见[参考文献](../reference/reading.md)。

## 参考文献

- Barkai O., Zhang B., Lenfers Turnes B., Arab M., Yarmolinsky D.A., Zhang Z., Barrett L.B., Woolf C.J. (2025). A machine learning tool with light-based image analysis for automatic classification of 3D pain behaviors. *Cell Reports Methods* 5(9):101145. https://doi.org/10.1016/j.crmeth.2025.101145 (PubMed 40876461)
- DeepLabCut bottom-up 9-keypoint mouse tracking model and training set of Barkai et al. (2025) [Data set]. Zenodo. https://doi.org/10.5281/zenodo.16321240（请按 Zenodo 页面显示的作者、标题和版本引用该记录）
- Zhang Z., Roberson D.P., Kotoda M., Boivin B., Bohnslav J.P., González-Cano R., Yarmolinsky D.A., Lenfers Turnes B., Wimalasena N.K., Neufeld S.Q., Barrett L.B., Quintão N.L.M., Fattori V., Taub D.G., Wiltschko A.B., Andrews N.A., Harvey C.D., Datta S.R., Woolf C.J. (2022). Automated preclinical detection of mechanical pain hypersensitivity and analgesia. *Pain* 163(12):2326–2336. https://doi.org/10.1097/j.pain.0000000000002680
- Jocher G., Qiu J., Liu M., Lyu S., Akyon F.C., Kalfaoglu M.E. (2026). Ultralytics YOLO26: unified real-time end-to-end vision models. *arXiv* 2606.03748. https://doi.org/10.48550/arXiv.2606.03748 · 软件：https://github.com/ultralytics/ultralytics (AGPL-3.0)
- Mathis A., Mamidanna P., Cury K.M., Abe T., Murthy V.N., Mathis M.W., Bethge M. (2018). DeepLabCut: markerless pose estimation of user-defined body parts with deep learning. *Nature Neuroscience* 21:1281–1289. https://doi.org/10.1038/s41593-018-0209-y
- Nath T., Mathis A., Chen A.C., Patel A., Bethge M., Mathis M.W. (2019). Using DeepLabCut for 3D markerless pose estimation across species and behaviors. *Nature Protocols* 14:2152–2176. https://doi.org/10.1038/s41596-019-0176-0
- Lin T.-Y. et al. (2014). Microsoft COCO: common objects in context. *ECCV 2014*, LNCS 8693:740–755. https://doi.org/10.1007/978-3-319-10602-1_48
- Apple Inc. (2025). *coremltools* (Version 9.0) [Computer software]. https://github.com/apple/coremltools (BSD-3-Clause)
