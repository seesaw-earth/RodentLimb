# 瘙痒（抓挠）

小鼠用后爪对瘙痒部位进行快速连续的抓挠。注射致痒剂后，观察者通常在 30–60 分钟内以 5 分钟为单位，统计抓挠回合数和抓挠时间（Kuraishi 等，1995）。RodentLimb 根据后爪在头部附近的快速来回运动找出这些回合。

## 拍摄

透过透明底板从下方拍摄，每个观察箱一只小鼠，**≥ 30 fps**（60 fps 更好：抓挠动作很快）。从注射开始录 30–60 分钟。如果视频开始得更早，请在参数中设置**注射时刻**；潜伏期、时间窗和分箱都从这一刻算起。见[拍摄视频](../guide/recording.md#per-task)。

## 如何检测抓挠

一帧同时满足以下条件时判为抓挠：

1. **一只后爪快速来回运动。** 它的*高频能量*（相对自身 0.2 秒滚动中位数的距离平方，在 0.5 秒内平均，单位为体长²）同时超过*能量阈值*（10^−2.6 体长²）和该视频静止爪的关键点抖动的 2.5 倍，因此跟踪噪声不会被计入。
2. **爪靠近头部**：在*头部距离*（0.65 体长）以内。
3. **身体保持原地**：速度低于*最大身体速度*（1.5 体长/秒）。

间隔小于*合并间隔*（0.5 秒）的抓挠帧组成一个**回合**，遵循“后爪放回地面或停顿即一次抓挠结束”的定义（Kuraishi 等，1995）。短于*最短回合*（0.3 秒）的回合被丢弃。抓挠的爪（左或右）是该回合中高频运动更多的那只。

间隔小于*抓挠串间隔*（2 秒）的回合组成**抓挠串**，因为在一次发作中抓挠和舔爪交替出现（Yu 等，2022）。

如果在 App 中加入了训练好的抓挠分类器（`ScratchModel.json`，用 Yu 等（2022）的 Scratch-AID 数据集训练），就会用它代替规则；方法学文字会说明这一点。发布的 App 使用关键点规则。

## 面颊模型：痒与痛

注射到面颊时，致痒剂引起后爪抓挠，致痛剂引起前爪擦脸（Shimada & LaMotte，2008）。选择*注射部位：面颊*时，RodentLimb 还会把**单侧前爪擦脸**作为疼痛样行为评分：一只前爪在脸部（距头部 0.22 体长以内）擦动，另一只前爪至少再远 0.12 体长，头朝前，身体在原地。双侧擦动属于理毛，不计入（Yamanoi 等，2019）。

## 复核

每个回合都列在**回放**中。可以把回合改标为*抓挠*、*前爪擦拭（痛样）*或*不是该行为（忽略）*；指标随之更新。

## 指标

| 指标 | 定义 |
|---|---|
| 抓挠次数 | 窗口内的回合数 |
| 抓挠时间 | 回合总时长（秒） |
| 首次抓挠潜伏期 | 从注射算起（秒） |
| 抓挠（占窗口 %） | 抓挠时间 ÷ 窗口 × 100 |
| 每分钟抓挠次数 | 回合数 ÷ 窗口长度 |
| 平均回合时长 · 最长回合 | 秒 |
| 抓挠串数 · 平均抓挠串时长 | 间隔 < 2 秒的回合合并 |
| 左 / 右后爪抓挠次数 · 侧别指数 | （L − R）÷（L + R）× 100 |
| 擦脸次数 · 擦脸时间 · 左 / 右前爪擦脸 | 仅面颊模型 |
| 人工修改事件 · 姿态覆盖率 | 数据质量 |

图表：从注射开始每个时间段的抓挠；事件时间轴。

## 参数

| 参数 | 默认 |
|---|---|
| 注射时刻 | 0 秒（视频开始） |
| 时间窗 | 注射后 0–30 分钟 |
| 时间分箱 | 5 分钟 |
| 注射部位 | 颈背部（或面颊） |
| 能量阈值 | 10^−2.6 体长²（0.5 秒均值） |
| 头部距离 | 0.65 体长 |
| 最大身体速度 | 1.5 体长/秒 |
| 合并间隔 · 最短回合 | 0.5 秒 · 0.3 秒 |
| 抓挠串间隔 | 2 秒 |

## 预设

| 预设 | 设置 | 来源 |
|---|---|---|
| **急性致痒剂：30 分钟**（默认） | 5 分钟分箱 | Park 等，2019；Kobayashi 等，2021；Yu 等，2022 |
| 自发 / 慢性瘙痒：60 分钟 | 10 分钟分箱 | 慢性瘙痒模型的常用做法（如 MC903、AEW） |

## 局限

- 抓挠动作很快；30 fps 时可能漏掉一些短回合。条件允许请用 60 fps。
- 抓挠身体侧面（而不是头颈部）时，爪可能在头部距离之外。
- 小鼠很少用后爪理脸，但这种情况看起来会很相似；请抽样复核。

## 参考文献

- Kuraishi Y., Nagasawa T., Hayashi K., Satoh M. (1995) Scratching behavior induced by pruritogenic but not algesiogenic agents in mice. *Eur J Pharmacol* 275:229–233.
- Shimada S.G., LaMotte R.H. (2008) Behavioral differentiation between itch and pain in mouse. *Pain* 139:681–687.
- Akiyama T., Carstens M.I., Carstens E. (2010) Differential itch- and pain-related behavioral responses and µ-opioid modulation in mice. *Acta Derm Venereol* 90:575–581.
- Yamanoi Y., Kittaka H., Tominaga M. (2019) Cheek injection model for simultaneous measurement of pain and itch-related behaviors. *J Vis Exp* 151:e58943.
- Yu H. et al. (2022) Scratch-AID, a deep learning-based system for automatic detection of mouse scratching behavior with high accuracy. *eLife* 11:e84042.
- Elliott P. et al. (2017) Automated acoustic detection of mouse scratching. *PLoS ONE* 12:e0179662.
