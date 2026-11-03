# 自我理毛

小鼠按从头到尾的顺序理毛：舔爪、洗鼻和脸、洗头、理身体、舔腿，最后理尾巴和生殖器（Kalueff 等，2007，2016）。除了理毛的量，它的**微结构**——被中断的回合以及违反从头到尾顺序的转换——对应激很敏感（Kalueff & Tuohimaa，2005）。RodentLimb 从仰视画面按身体部位为理毛评分。

## 拍摄

透过透明底板从下方拍摄，一只小鼠，**≥ 30 fps**。常用短暂适应后 10 分钟；喷雾实验在喷雾后立即开始。见[拍摄视频](../guide/recording.md#per-task)。

## 如何检测理毛

从下方可以区分四个部位，每个部位只在身体速度低于 1.0 体长/秒时判定：

| 部位 | 规则 |
|---|---|
| **脸 / 头** | 两只前爪（或一只，另一只被遮挡）在嘴的 0.20 体长以内，并且在擦动：前爪快速运动，高于擦动能量（10^−3.2 体长²），也高于该视频自身的关键点抖动 |
| **身体（侧腹）** | 头部相对躯干轴线转过 50° 以上，并且头在运动 |
| **后腿 / 后爪** | 嘴在一只后爪的 0.30 体长以内 |
| **尾 / 生殖器** | 鼻尖在尾根的 0.40 体长以内（身体蜷起） |

头部附近的后爪抓挠被排除，并单独报告。短于 0.5 秒的部位片段被丢弃。

**回合。** 超过*回合间隔*（5 秒；Estanislau，2012）的停顿结束一个回合；短于 1.0 秒的回合被丢弃。包含至少 1 秒停顿的回合算作**被中断**。部位之间的转换沿着脸 → 身体 → 腿 → 尾的链条向下时为**正确**；错误转换百分比和中断回合百分比是微结构指标。各实验室对回合和停顿的阈值不同，因此这些阈值会写入方法学导出。

四部位链条比观察者的量表粗略；请把微结构视为探索性指标。

## 复核

每个回合都列在**回放**中，可以改标为*理毛*或*不是该行为（忽略）*。

## 指标

| 指标 | 定义 |
|---|---|
| 理毛时间 · 理毛（占窗口 %） | 秒 · % |
| 理毛次数 · 首次理毛潜伏期 | 次 · 秒 |
| 平均回合时长 · 最长回合 | 秒 |
| 脸 / 头 · 身体（侧腹） · 后腿 / 后爪 · 尾 / 生殖器 | 各部位时间（秒） |
| 脸部在理毛中的占比 | % |
| 被中断的回合 | 占回合 % |
| 错误（非从头到尾）转换 · 部位转换次数 | % · 次 |
| 抓挠（已排除） | 秒 |
| 人工修改事件 · 姿态覆盖率 | 数据质量 |

图表：每个时间段的理毛；各部位随时间变化的行为谱。

## 参数

| 参数 | 默认 |
|---|---|
| 时间窗 · 时间分箱 | 0–10 分钟 · 1 分钟 |
| 脸部距离 | 0.20 体长 |
| 腿部距离 | 0.30 体长 |
| 尾部距离 | 0.40 体长 |
| 转头角度 | 50° |
| 最大身体速度 | 1.0 体长/秒 |
| 擦动能量 | 10^−3.2 体长² |
| 最短部位片段 | 0.5 秒 |
| 回合间隔 · 最短回合 | 5 秒 · 1.0 秒 |

## 预设

| 预设 | 设置 | 来源 |
|---|---|---|
| **10 分钟实验**（默认） | 停顿 > 5 秒结束一个回合 | Estanislau，2012 |
| Kalueff：5 分钟，6 秒回合 | 短于 6 秒的停顿算回合内的中断 | Kalueff & Tuohimaa，2004；Kalueff 等，2007 |
| 适应 10 分钟后（10–20 分钟） | 自闭症模型实验方案 | McFarlane 等，2008；Silverman 等，2010 |

## 局限

- 从下方无法区分链条开头的舔爪和洗脸。
- 近红外模型没有嘴的关键点，改用吻端，这会使脸部和腿部理毛的判断不那么确定。

## 参考文献

- Kalueff A.V., Tuohimaa P. (2004) Grooming analysis algorithm for neurobehavioural stress research. *Brain Res Protoc* 13:151–158.
- Kalueff A.V., Tuohimaa P. (2005) Mouse grooming microstructure is a reliable anxiety marker bidirectionally sensitive to GABAergic drugs. *Eur J Pharmacol* 508:147–153.
- Kalueff A.V., Aldridge J.W., LaPorte J.L., Murphy D.L., Tuohimaa P. (2007) Analyzing grooming microstructure in neurobehavioral experiments. *Nat Protoc* 2:2538–2544.
- Kalueff A.V. et al. (2016) Neurobiology of rodent self-grooming and its value for translational neuroscience. *Nat Rev Neurosci* 17:45–59.
- Estanislau C. (2012) Cues to the usefulness of grooming behavior in the evaluation of anxiety in the elevated plus-maze. *Psychol Neurosci* 5:105–112.
- McFarlane H.G. et al. (2008) Autism-like behavioral phenotypes in BTBR T+tf/J mice. *Genes Brain Behav* 7:152–163.
- Silverman J.L., Yang M., Lord C., Crawley J.N. (2010) Behavioural phenotyping assays for mouse models of autism. *Nat Rev Neurosci* 11:490–502.
