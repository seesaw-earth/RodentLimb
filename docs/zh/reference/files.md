# 文件与导出

## 数据存放位置

**文件 › 我的 iPhone › RodentLimb › RodentLimb › Sessions**，每条记录一个文件夹：

| 文件 | 内容 |
|---|---|
| `session.json` | 动物编号、组别、备注、范式、参数、标定、标签修改 |
| `video.mov` / `.mp4` | 导入视频的副本 |
| `pose.plist` | 每一帧的关键点（二进制属性列表） |
| `result.json` | 最近一次分析结果 |
| `skeleton.mp4` | 仅在打开“同时生成骨架视频”时生成 |

## 单条记录导出

所有文件名以 `<动物编号>_<范式>` 开头（范式 = TST、CYL 或 GAIT）。所有文字均为英文。

### `…_summary.csv`

长表格式，列为 `field, value, unit`：记录信息（subject、group、assay、video、created、fps、duration_s、model、model_version、notes），然后是按键名列出的所有指标，最后是提示（`note_info`、`note_warning`、`note_error`）。

### 悬尾

- `…_immobility_bouts.csv`：`bout, start_s, end_s, duration_s, overlaps_window`
- `…_per_minute.csv`：`minute, immobility_s`

### 圆筒

- `…_contacts.csv`：`event, onset_s, offset_s, rear, auto_label, final_label, edited, counted`。标签为 `left`、`right`、`both` 或 `ignore`。

### 步态

- `…_strides.csv`：`paw, start_s, end_s, stride_s, stance_s, swing_s, duty, stride_length_<unit>, speed_<unit>_per_s`（unit = `cm` 或 `BL`）。做速度校正统计时请使用每步速度。
- `…_footprints.csv`：`paw, strike_s, x_px, y_px`

### `…_methods.txt`

包含参数值和该范式参考文献的方法描述。

### `…_pose.csv`（可选）

`frame, time_s, box_confidence`，然后是每个关键点的 `<keypoint>_x, <keypoint>_y, <keypoint>_confidence`，关键点依次为 `L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth`。坐标为显示画面（已校正旋转）中的像素，原点在左上角。缺失点的 x/y 为空。

## 批量导出

在“数据”页（**选择 › 导出 CSV**）：每个范式一个文件，`RodentLimb_<范式>_<n>_sessions_<日期>.csv`。每条记录一行：`subject, group, video, created, status`，然后每个指标一列，列名为 `键名 [单位]`。

## 指标键名

键名在各版本间保持不变，脚本可以放心依赖。例如：`immobility_s`、`immobility_pct`、`latency_s`、`contra_use_pct`、`asymmetry_pct`、`stride_len_hind`、`duty_hind`、`bos_hind`、`ref_stride_len_bl`、`phase_LH_RH`、`pattern_trot_pct`、`nose_lateral_amp_bl`。每个范式的页面列出了其全部指标。
