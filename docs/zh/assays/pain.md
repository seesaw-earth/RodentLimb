# 自发痛行为

向爪内注射（福尔马林、辣椒素、CFA 等）后，小鼠会舔咬该爪并缩爪/甩爪。在福尔马林实验中，这些行为分为早期的 **I 相**（直接激活伤害感受器）和晚期的 **II 相**（炎症和中枢敏化）（Dubuisson & Dennis，1977；Hunskaar & Hole，1987）。RodentLimb 从仰视画面测量注射爪的舔咬和甩爪。

## 拍摄

透过透明底板从下方拍摄，使注射爪可见，**≥ 30 fps**，正常光照。福尔马林：从注射起录 45–60 分钟；辣椒素：5–10 分钟。在参数中设置**注射爪**和**注射时刻**。见[拍摄视频](../guide/recording.md#per-task)。

## 如何检测行为

**舔咬。** 嘴（没有识别嘴时用鼻尖，例如近红外模型）在注射爪的*舔爪距离*（0.30 体长）以内，且身体速度低于 1.5 体长/秒。两只爪都这么近时，算给更近的那只。间隔小于 1.0 秒的片段合并；短于 0.5 秒的片段丢弃。嘴与注射爪的任何接触都计入（Wotton 等，2020）。对另一只爪的舔咬以同样方式测量，作为同一动物内的对照（理毛也包括舔爪）。

**甩爪 / 抖爪。** 注射爪一次短暂（≤ 0.30 秒）、快于*甩爪速度*（4.0 体长/秒，约 33 毫秒内测量；跟踪噪声较大时提高到该爪静止时中位速度的 4 倍）的运动，同时：

- 前后 ±0.3 秒内身体速度低于 1.0 体长/秒，
- 另一只爪在同一时刻没有同样快地运动（那会是左右标签互换），并且
- 0.5 秒内没有舔咬（爪不是正在被抬到嘴边或放下）。

护爪和负重需要爪的接触面积或压力，关键点无法提供，因此不评分。

## 分相

默认 I 相 = 注射后 0–10 分钟，II 相 = 10–60 分钟（Mogil 等，1999），5 分钟分箱。其他已发表的分相方式可以通过预设选择。

## 复核

每个事件都列在**回放**中。可以改标为*舔咬注射爪*、*甩爪 / 抖爪*、*舔对侧爪*或*不是该行为（忽略）*。

## 指标

| 指标 | 定义 |
|---|---|
| 舔咬时间：I 相 · II 相 · 间期 · 整个窗口 | 注射爪的舔咬时间（秒） |
| 舔咬次数 · 首次舔咬潜伏期 · 平均舔咬时长 | |
| 甩爪次数 · I 相 · II 相甩爪次数 | 次数 |
| 舔对侧爪 | 秒 |
| 注射爪在舔爪中的占比 | 注射爪 ÷（注射爪 + 对侧爪）× 100 |
| 注射爪可见率 | 识别到注射爪的帧所占百分比 |
| 人工修改事件 · 姿态覆盖率 | 数据质量 |

图表：每个时间段的舔咬时间和甩爪次数；事件时间轴。

## 参数

| 参数 | 默认 |
|---|---|
| 注射时刻 | 0 秒 |
| 注射爪 | 右后爪 |
| I 相结束 · II 相 | 10 分钟 · 10–60 分钟 |
| 时间分箱 | 5 分钟 |
| 舔爪距离 | 0.30 体长 |
| 最大身体速度（舔咬） | 1.5 体长/秒 |
| 最短舔咬 · 合并间隔 | 0.5 秒 · 1.0 秒 |
| 甩爪速度 · 最长甩爪时长 | 4.0 体长/秒 · 0.30 秒 |
| 甩爪时身体静止 | < 1.0 体长/秒 |

## 预设

| 预设 | 分相 | 来源 |
|---|---|---|
| **福尔马林 0–10 / 10–60 分钟**（默认） | 5 分钟分箱 | Mogil 等，1999 |
| 福尔马林 0–5 / 20–30 分钟 | 小鼠舔爪的两个峰 | Hunskaar 等，1985；Hunskaar & Hole，1987 |
| 福尔马林 0–5 / 20–40 分钟 | 小鼠实验方案 | Nian 等，2014 |

## 局限

- 甩爪很快；30 fps 时短的甩爪可能被漏掉或合并。
- 注射爪必须从下方可见；收在身体下面的爪无法识别。
- 近红外模型没有嘴的关键点，改用吻端。

## 参考文献

- Dubuisson D., Dennis S.G. (1977) The formalin test: a quantitative study of the analgesic effects of morphine, meperidine, and brain stem stimulation in rats and cats. *Pain* 4:161–174.
- Hunskaar S., Hole K. (1987) The formalin test in mice: dissociation between inflammatory and non-inflammatory pain. *Pain* 30:103–114.
- Tjølsen A., Berge O.G., Hunskaar S., Rosland J.H., Hole K. (1992) The formalin test: an evaluation of the method. *Pain* 51:5–17.
- Mogil J.S. et al. (1999) Heritability of nociception I: responses of 11 inbred mouse strains on 12 measures of nociception. *Pain* 80:67–82.
- Wotton J.M. et al. (2020) Machine learning-based automated phenotyping of inflammatory nocifensive behavior in mice. *Mol Pain* 16:1744806920958596.
