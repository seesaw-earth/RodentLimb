# 资料库与文件

## 资料库

RodentLimb 的所有数据都保存在一个文件夹中，即**资料库**。默认位于 App 容器内的 `Documents/RodentLimb`；**文件 › 在访达中显示资料库** 可以打开它。用 **文件 › 打开资料库…** 可以把资料库放在任何地方，例如外置硬盘上的项目文件夹。

```
RodentLimb/
├── Experiments/<id>.json        研究：设计、动物、分组、盲法、QC 标准
├── Recordings/<id>/             每段视频一个文件夹
│   ├── recording.json           动物、时间点、QC 报告、纳入 / 排除及原因
│   ├── pose.bin                 每一帧的关键点（每小时视频几 MB）
│   ├── source.json              视频在哪里（书签、路径、指纹）以及用哪个姿态模型识别
│   ├── checkpoint/              识别中的检查点；完成后删除
│   └── thumbnail.jpg            列表缩略图
├── Sessions/<id>/               每个分析一个文件夹（一段视频 × 一个任务）：
│                                session.json（参数、标定、人工修改）和 result.json
├── Logs/activity-<日期>.log     批处理日志：导入、每段视频、失败、恢复
├── Recently Deleted/<id>/       已删除的项目，保留 30 天
├── Backups/metadata-<日期>-<原因>.json   研究、视频信息和参数的备份
└── .rodentlimb-lock.json        哪台 Mac 正在使用这个资料库
```

目录结构与 iPhone 版的资料库相同，因此从 **文件 › 我的 iPhone › RodentLimb** 拷贝来的资料库可以在 Mac 上打开。

**视频默认不复制。** RodentLimb 在原位置引用视频（沙盒安全范围书签），不额外占用硬盘空间。如果你希望资料库自成一体，可以在导入时的*视频文件*中选择复制，或在设置中打开*默认将视频复制到资料库*。存有引用视频的硬盘拔出后，这些视频显示为离线，并在队列中等待硬盘重新连接。

## 安全措施

- **最近删除**（**文件 › 最近删除…**，⌥⌘⌫）。删除视频、分析或研究时，其文件夹移入 `Recently Deleted/` 保留 30 天，可一键恢复。视频会连同其分析一起恢复。以引用方式导入的原始视频文件从不删除。
- **备份。** 每天打开资料库时，以及在删除和批量修改（批量纳入 / 排除、参数*应用到…*）之前，RodentLimb 把研究、视频信息、纳入决定、分析参数和人工标签写入 `Backups/`（一个紧凑的 JSON 文件；保留最近 14 个每日备份和 10 个修改前备份）。在 **设置 › 高级 › 数据安全** 中恢复。恢复不改变识别结果，不删除任何内容，并会先备份当前状态。
- **资料库锁。** 某台 Mac 打开资料库期间，`.rodentlimb-lock.json` 每分钟刷新一次。如果第二台 Mac 打开同一资料库（共享盘、iCloud 云盘），会收到提醒，避免互相覆盖。锁文件记录该 Mac 的名称和 macOS 用户名，从不上传到任何地方。
- **检查点。** 识别时把每一帧的关键点写入 `checkpoint/`，至少每 2 秒落盘一次。暂停、退出、睡眠、崩溃或断电后，从最后一个完整帧之后继续，结果与一次跑完相同。

## `pose.bin`

一段视频的关键点，由识别过程写入一次。小端字节序：

```
"RLPS" · UInt32 版本 (1) · UInt32 头部长度 · 头部 JSON ·
时间 (Float64 × n) · 检测框置信度 (Float32 × n) ·
每个关键点：x, y, 置信度（各 Float32 × n）
```

头部包含画面尺寸、帧率、时长以及姿态模型的名称和版本。关键点顺序：`L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth`。坐标为显示画面（已校正旋转）中的像素，原点在左上角；缺失的关键点 x = y = −1、置信度为 0。1.2.1 之前的资料库保存的是 `pose.plist`；它会被读取并一次性转换为 `pose.bin`。

你不需要自己读取 `pose.bin`：导出会把同样的数据写成 CSV（`pose/`）和 DeepLabCut 格式（`pose_dlc/`）。

## 导出文件

导出文件夹及其中的表格见[导出](../guide/export.md)。导出始终为英文。汇总表的前 10 列相同，可按 `analysis_id` 关联；指标列命名为 *键名 [单位]*。

### 逐帧姿态（`pose/`）

`frame, time_s, box_confidence`，然后是七个关键点的 `<keypoint>_x, <keypoint>_y, <keypoint>_confidence`，单位为显示画面的像素。缺失的点 x 和 y 为空。

### DeepLabCut 格式（`pose_dlc/`）

三行表头（scorer、bodyparts、coords）：7 个部位 × `x, y, likelihood`。用 `pandas.read_csv(f, header=[0, 1, 2], index_col=0)` 读取。可在 DeepLabCut、SimBA 和 Keypoint-MoSeq 中打开。

## 指标键名

键名在各版本之间保持稳定，脚本可以依赖它们。示例：

| 任务 | 键名 |
|---|---|
| 悬尾实验 | `immobility_s`、`immobility_pct`、`latency_s` |
| 圆筒实验 | `contra_use_pct`、`asymmetry_pct` |
| 步态分析 | `stride_len_hind`、`duty_hind`、`bos_hind`、`ref_stride_len_bl`、`phase_LH_RH`、`pattern_trot_pct` |
| 瘙痒 | `scratch_bouts_n`、`scratch_time_s`、`latency_s`、`bouts_per_min`、`trains_n`、`side_index_pct` |
| 自发痛行为 | `lick_phase1_s`、`lick_phase2_s`、`flinch_n`、`lick_latency_s`、`lick_ipsi_share_pct` |
| 自我理毛 | `groom_time_s`、`groom_bouts_n`、`face_s`、`interrupted_pct`、`incorrect_transitions_pct` |
| 癫痫发作评分 | `max_stage`、`latency_jerk_s`、`latency_generalized_s`、`latency_tonic_s`、`jerks_n`、`episodes_n` |
| 所有任务 | `edited_n`、`pose_coverage_pct` |

每次导出的 `README.txt` 列出每个文件的每一列。
