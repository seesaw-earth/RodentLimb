# 导出

按 ⌘E（**文件 › 导出…**），选择**范围**（所选内容、一个任务、一个研究或整个资料库）和文件类型，再选择一个文件夹。RodentLimb 写出一个文件夹：

```
RodentLimb_<范围>_<日期_时间>/
├── README.txt                  数据字典：每个文件、每一列是什么
├── export_manifest.json        App 和模型版本、导出选项、每个分析的参数、标定和人工修改次数
├── qc_videos.csv               识别质量、QC 结论、纳入/排除及原因、姿态模型
├── study_<名称>_design.txt     研究的设计和方法学文字
├── ITCH_Itch_scratching/       每个任务一个文件夹
│   ├── ITCH_summary.csv        每个分析一行：设计列、QC，然后是全部指标
│   ├── ITCH_segments.csv       所有视频的每个事件或回合（开始、结束、时长、注射后时间、
│   │                           自动标签、复核后标签、是否修改、是否计入）
│   ├── ITCH_ethogram.csv       每条轨道的行为区间
│   ├── ITCH_time_bins.csv      从注射开始的时间分箱进程（长格式）
│   ├── ITCH_methods.txt        带参数和参考文献的方法学段落
│   ├── ITCH_boris_events.tsv   （可选）BORIS aggregated events
│   ├── frame_labels/           （可选）逐帧 0/1 标签（DeepEthogram / daart）
│   └── per_video/              （可选）每段视频一个文件夹，与 iPhone 导出单个分析相同
├── pose/                       （可选）逐帧关键点，RodentLimb 格式
└── pose_dlc/                   （可选）DeepLabCut 格式的关键点
```

## 数据表

- 所有汇总表的前 10 列相同——`analysis_id`、`study`、`animal_id`、`blind_code`、`sex`、`group`、`timepoint`、`trial`、`video`、`included`——因此可以按 `analysis_id` 关联。指标列命名为 *键名 [单位]*。
- 表格为**长格式**，可直接用于 R、Python、SPSS 或 Prism（双因素或混合方差分析，或以动物为随机效应的线性混合模型）。
- **片段表**：悬尾写出不动和爬尾回合（另有逐分钟表）；圆筒写出每次触壁；步态写出步幅表和足印表。
- 文件为带 BOM 的 UTF-8，Excel 打开中文编号不会乱码。BORIS 和逐帧标签文件不带 BOM。
- 无论界面语言是什么，导出始终为英文。

## 互通

| 文件 | 可用于 |
|---|---|
| `*_boris_events.tsv` | BORIS，作为 aggregated events |
| `frame_labels/` | DeepEthogram、daart |
| `pose_dlc/` | DeepLabCut、SimBA、Keypoint-MoSeq（用 `pandas.read_csv(f, header=[0, 1, 2], index_col=0)` 读取：7 个部位 × x, y, likelihood） |

## 盲态研究

研究处于盲态时，导出不写出动物编号、分组和原始文件名；用盲码识别每只动物。

## 方法学段落

`*_methods.txt` 为每个分析描述姿态模型、关键点预处理、带参数值的评分规则、人工修改次数和参考文献。第一句写明识别该视频的模型。可以复制到论文的方法部分再修改；另见[如何引用](../models/cite.md)。
