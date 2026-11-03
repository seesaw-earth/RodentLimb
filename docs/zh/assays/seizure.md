# 癫痫发作评分

给予致惊厥剂后的行为性发作通常用 Racine 类量表评分（Racine，1972）。RodentLimb 从仰视画面找出候选发作事件，估计达到的分级并报告潜伏期。**每个事件都只是初筛，需要复核者在视频上确认。**

## 拍摄

透过透明底板或圆筒从下方拍摄，一只小鼠，**≥ 30 fps**，正常光照。在注射致惊厥剂之前开始，注射后至少录 30 分钟；在参数中设置**注射时刻**。见[拍摄视频](../guide/recording.md#per-task)。

## 量表

**小鼠 PTZ——修订版 Racine 量表**（Van Erum 等，2019，在 Lüttjohann 等 2009 的基础上扩展）：
0 胡须颤动 · 1 突然的行为停顿、凝视不动 · 2 面部抽动 · 3 颈部抽动 · 4 坐姿阵挛发作 · 5 俯卧的阵挛或强直-阵挛发作 · 6 侧卧和/或狂跳 · 7 强直伸展。0–2 级为局灶性，3–6 级为全面性。

**海人酸 / 毛果芸香碱——改良 Racine 量表**（Racine，1972；Sharma 等，2018）：
1 不动 · 2 面部自动症 · 3 前肢阵挛 · 4 站立并跌倒 · 5 全面性强直-阵挛发作，伴侧卧、跳跃或狂奔。

从下方看不到胡须颤动和面部抽动，因此不评分。

## 候选事件

| 事件 | 分级（PTZ / 海人酸量表） | 规则 |
|---|---|---|
| **肌阵挛抽动** | 3 / 2 | 全身性抽动：关键点速度的中位数（约 33 毫秒内）超过 4.0 体长/秒，至少 4 个身体部位快于该速度的一半，持续 ≤ 0.5 秒，之前动物安静（前 0.5 秒 < 1.0 体长/秒）；之后 0.5 秒内身体移动不超过 0.4 体长 |
| **直立阵挛发作** | 4 / 3 | 至少 3 个身体部位（包括一只前爪和一只后爪）有节律地快速运动，高于 max(10^−2.4 体长², 5 × 抖动)，身体在原地，持续 ≥ 3 秒（NINDS 皮下 PTZ 终点：阵挛约 3–5 秒） |
| **俯卧抽搐 / 跌倒** | 5 / 4 | 不单独检测：小鼠俯卧时，把阵挛发作改标为此类 |
| **侧卧抽搐** | 6 / 5 | 所有爪都在身体轴线的同一侧（侧腹朝向相机），持续 ≥ 1 秒 |
| **狂奔 / 跳跃** | 6 / 5 | 身体速度 > 8.0 体长/秒持续 ≥ 0.3 秒，或动物在 1 秒内于 1.5 体长以外重新出现 |
| **后肢强直伸展** | 7 / 5 | 两只后爪伸到尾根后方并保持僵直（< 1 体长/秒），持续 ≥ 1 秒 |
| **行为停顿**（默认关闭） | 1 / 1 | 在运动之后、首次全面性发作之前，运动 < 0.15 体长/秒持续 ≥ 5 秒。从下方看，停顿与普通的休息很像，因此只有在基线活跃时才有意义 |

重叠的检测取较高的分级；间隔小于 5 秒的全面性事件合并为一次**发作**（Van Erum 等，2019 把间隔 < 5 秒的脑电事件合并）。**注射前**的检出会列出但不计入；它们的数量是内置的假阳性检查。

## 复核

每个事件都和分级一起列在**回放**中。在视频上确认或改标，或标为*不是该行为（忽略）*；分级、潜伏期和次数随之更新。

## 指标

| 指标 | 定义 |
|---|---|
| 最高分级（估计） · 达到最高分级用时 | |
| 首次肌阵挛潜伏期 | 从注射算起（秒） |
| 首次全面性发作潜伏期 | ≥ 3 级（PTZ 量表） |
| 侧卧抽搐 / 跳跃潜伏期 · 后肢强直伸展潜伏期 | 秒 |
| 肌阵挛次数 · 直立阵挛发作 · 失去姿态的抽搐、跳跃或强直伸展 | 次数 |
| 全面性发作总时长 · 发作次数（合并后） · 最长一次发作 | |
| 行为停顿次数 | 评分时 |
| 疑似死亡 | 强直伸展后无运动 |
| 注射前检出（基线） | 假阳性检查 |
| 人工修改事件 · 姿态覆盖率 | 数据质量 |

## 参数

| 参数 | 默认 |
|---|---|
| 注射时刻 | 0 秒 |
| 量表 | 小鼠 PTZ（Van Erum 2019，1–7 级） |
| 注射后观察时长 · 时间分箱 | 30 分钟 · 1 分钟 |
| 抽动速度 · 最长时长 · 安静速度 | 4.0 体长/秒 · 0.5 秒 · 1.0 体长/秒 |
| 阵挛能量 · 最短时长 | 10^−2.4 体长² · 3.0 秒 |
| 失去姿态的最短时长 | 1.0 秒 |
| 奔跑速度 · 最短时长 | 8.0 体长/秒 · 0.3 秒 |
| 强直伸展的最短时长 | 1.0 秒 |
| 评分行为停顿 | 关（开启时：5 秒，< 0.15 体长/秒） |
| 发作间隔 | 5 秒 |

## 预设

| 预设 | 设置 | 来源 |
|---|---|---|
| **PTZ：30 分钟**（默认） | 修订版 Racine 量表（1–7 级） | Van Erum 等，2019 |
| 海人酸 / 毛果芸香碱：2 小时 | 改良 Racine 量表（1–5 级），10 分钟分箱 | Racine，1972；Sharma 等，2018 |

::: warning 自动分级只是估计
发作分级由观察者看着动物（常常结合脑电）来定义。自动分级是复核的起点，而不是替代。请报告有多少事件被确认或改标（方法学文字会统计修改次数）。
:::

## 参考文献

- Racine R.J. (1972) Modification of seizure activity by electrical stimulation. II. Motor seizure. *Electroencephalogr Clin Neurophysiol* 32:281–294.
- Lüttjohann A., Fabene P.F., van Luijtelaar G. (2009) A revised Racine's scale for PTZ-induced seizures in rats. *Physiol Behav* 98:579–586.
- Van Erum J., Van Dam D., De Deyn P.P. (2019) PTZ-induced seizures in mice require a revised Racine scale. *Epilepsy Behav* 95:51–55.
- Ferraro T.N. et al. (1999) Mapping loci for pentylenetetrazol-induced seizure susceptibility in mice. *J Neurosci* 19:6733–6739.
- Sharma S., Puttachary S., Thippeswamy A., Kanthasamy A.G., Thippeswamy T. (2018) Status epilepticus: behavioral and electroencephalography seizure correlates in kainate experimental models. *Front Neurol* 9:7.
- Copping N.A., Silverman J.L. (2021) Abnormal electrophysiological phenotypes and sleep deficits in a mouse model of Angelman syndrome. *Mol Autism* 12. https://doi.org/10.1186/s13229-021-00416-y
