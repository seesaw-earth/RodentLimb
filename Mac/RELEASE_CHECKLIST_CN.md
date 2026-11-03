# RodentLimb for Mac — 编译、测试与上架清单

## A. 第一次编译
- [ ] 解压后先在终端运行 `sh tools/app_store_preflight.sh`（见 C1），再用 Xcode 26 或更高版本打开 `macOS/RodentLimb.xcodeproj`，Signing 选 Team，Bundle ID `com.ziqingshi.rodentlimb`。
- [ ] Product › Build（⌘B）。如有错误，复制完整错误列表发给我。
- [ ] 命令行先跑核心测试：`sh tools/run_core_tests.sh`（需 Xcode 命令行工具；Python 3 + pandas 可选，用于检查导出）。

## B. 功能测试（建议用 10–20 段真实视频，含 1 段长视频 ≥ 30 min、1 段手机竖拍视频、1 段 AVI）
- [ ] 在任务中把一个文件夹拖进窗口 → 添加视频表格读出时长 / 帧率；AVI 提示需转换；文件名规则正确填入动物 / 组别 / 时间点。
- [ ] 开始识别：队列有实时画面与关键点、进度、帧率、剩余时间；Dock 图标有进度条。
- [ ] 识别中按 ⌘.（暂停）→ 再 ⌘R：从中断处继续（队列卡片显示“从检查点继续”）。
- [ ] 识别中 ⌘Q → 确认退出 → 重新打开：自动从中断处继续。
- [ ] 识别中强制退出（活动监视器 › 强制退出）→ 重新打开：从检查点继续；日志记录“unexpected stop”。
- [ ] 识别中拔掉存放视频的移动硬盘：该视频回到队列标“离线”，其他视频继续；插回后点开始自动完成。
- [ ] 手机竖拍视频：关键点叠加方向正确（与 iPhone 版结果一致）。
- [ ] 待复核：I / E / ↓ 快速复核；排除原因写入导出的 qc_videos.csv。
- [ ] 打开会话 → 三个标签；改参数实时重算；复核页改事件标签后指标更新。
- [ ] 圆筒标定 / 步态标尺；“应用到全部”。
- [ ] 任务设计：随机分组、盲法（盲态下导出不含编号 / 组别 / 文件名）、组间比较图。
- [ ] 导出全部选项 → 用 Excel 打开 summary / segments（中文编号不乱码）；DLC 文件用 `pandas.read_csv(f, header=[0,1,2], index_col=0)` 读取。
- [ ] 把 iPhone 的 RodentLimb 文件夹（文件 App › 我的 iPhone › RodentLimb）拷到 Mac → 文件 › 打开资料库：研究、结果都在；视频若在文件夹内可直接回放。
- [ ] 同一视频在 iPhone 与 Mac 上识别：关键点与指标一致（GPU / 神经网络引擎的浮点差异应 < 0.5 px）。
- [ ] 通宵批处理 50+ 段视频：内存平稳（活动监视器），第二天收到通知、日志完整。
- [ ] 深色模式、中英文切换（设置 › 通用 › 语言）、Intel Mac（如有）。

### 1.4.2 稳定性（布局死循环、卡顿）
- [ ] 把窗口拖到最小（860 × 560），依次打开：首页、任务页（含很长的备注）、处理队列（识别 3 个以上视频时）、全部视频（显示检查器）、视频页、会话复核页；窗口不会自行变大、跳到屏幕外，也不闪退。
- [ ] 识别进行中：快速来回拖动窗口宽度 20 秒（跨过 1040 / 1120 宽度，检查器自动隐藏 / 恢复），不闪退、不卡住。
- [ ] 识别进行中打开会话页（“等待识别”状态），窗口高度不随进度跳动。
- [ ] 会话复核页：拖动宽度跨过 720 / 800，事件列表在下方 / 右侧之间切换，不来回闪动。
- [ ] 视频页 QC 播放器播放 30 秒：活动监视器中 CPU 不持续满载；拖动进度条流畅。
- [ ] 快速打开、返回同一个视频页 10 次：日志中 FigFilePlayer 报错不再成串出现，内存不持续增长。
- [ ] 从全部视频 → 视频 → 分析 → 再打开同一视频：返回到已有页面，不重复推入。
- [ ] 识别 50+ 段视频的资料库：侧栏百分比、队列页剩余时间更新时界面不卡顿。

### 1.4.1 布局
- [ ] 系统设置 › 显示器 选“更大字体”（或在 13 英寸 Mac 上）：主窗口可完整放进屏幕；把窗口缩到最小 860 × 560。
- [ ] 窗口最小、且放在屏幕下半部时，依次打开：新建任务、添加视频、导出、移到任务、标定、编辑设计、添加动物、最近删除——每个窗口都在屏幕内，底部按钮都点得到，内容可滚动。
- [ ] 缩窄窗口：任务页“添加视频 / 导出”移到标题下方；视频页决定栏移到下方；会话“回放”页事件列表移到视频下方；处理队列的“开始 / 暂停”移到状态下方；检查器自动隐藏，拉宽后恢复。
- [ ] 同时识别 3 个视频且有失败视频时，窗口高度最小：等待队列表格和按钮仍可见。
- [ ] 侧栏“新建任务…”整行可点；语言按钮和“显示”按钮易点中。

### 1.4.0 先选任务，再处理视频
- [ ] 空资料库：首页只有“新建任务…”；⇧⌘N → 选“步态分析” → 名称留空（自动为“步态分析 日期”）、组别填 Sham / SNI → 创建：侧栏出现任务并展开两个组。
- [ ] 把一个含 `M1_sham.mp4`、`M2_SNI.mp4` 的文件夹拖入窗口：添加视频表格的组别列自动选中 Sham / SNI；改一行组别；批量设组；添加 → 任务页会话列表立即出现这些视频，状态为“排队中 / 识别中 xx%”。
- [ ] 识别完成：通过 QC 的会话变为“已完成”，其余为“待复核”；任务页“复核”按钮 → I / E；结果标签显示每组散点（均值 ± 标准误、n）。
- [ ] 侧栏选某一组：任务页只显示该组的会话和计数。
- [ ] 会话右键“移出任务” → 底部“撤销” → 会话回来；“移到其他任务…”到另一个任务。
- [ ] 没有选中任务时拖入视频：先出现“新建任务”，可选“加入已有任务”；创建后自动打开添加视频表格。
- [ ] 打开一个 1.3 资料库（含多任务研究）：显示为“研究名 · 范式”多个任务；没有范式的研究在“未归入任务”中“设为任务”。
- [ ] 删除任务（保留视频）→ 视频出现在“未归入任务”；文件 › 最近删除… 恢复。
- [ ] 界面中除播放控制和展开箭头外没有图标；深色模式下图表和状态颜色清楚。
- [ ] 导入表格的姿态模型只有两项：可见光（FP16，默认）、近红外（暗箱）。
- [ ] 打开一个旧资料库：已识别视频的“姿态模型”显示 CylinderMousePoseV2；重新识别改用 FP16。
- [ ] 导入一段 AV1 视频（M1/M2 Mac）：导入表格标为“无法读取”并给出转换方法。

### 1.3.2 近红外模型
- [ ] 导入 2–3 段暗箱近红外视频，“姿态模型”选第二项：处理队列卡片显示“近红外（暗箱）”，实时画面中关键点落在爪、尾根和鼻尖上。
- [ ] QC 播放器中检查关键点；没有“嘴”点、鼻尖–嘴连线不显示属正常。
- [ ] 同一段视频分别用两个模型识别（视频页 › 更多 › 重新识别…），比较 QC 覆盖率。
- [ ] 导出：`qc_videos.csv` 的 `pose_model` 列、`*_methods.txt` 第一句、manifest 的 `pose_model`。

### 1.3.1 修复与新功能的回归测试
- [ ] 导入 3–5 段视频（不勾选任务）→ 识别完成：处理队列页显示“全部视频已识别完成”和下一步按钮；底部提示条出现“复核/查看”。
- [ ] 识别完成后依次打开“待复核”“全部视频”“研究”页、上下切换视频、打开检查器：不卡、不闪退（以前的 `No Observable object of type AppModel found`）。
- [ ] 双击视频进入 QC 播放器，播放、拖动、逐帧；返回列表再进入另一段视频。
- [ ] 语言：菜单栏 RodentLimb › Language · 语言、侧栏底部“EN / 中文”、设置分别切换；界面立即切换；选“立即重新启动”后系统菜单（编辑/窗口）也变为中文；识别中切换并重启后从检查点继续。
- [ ] 删除 1 段视频 → 底部“撤销” → 视频和分析回来；再删除 → 文件 › 最近删除… → 恢复；删除研究（保留视频）→ 恢复研究 → 视频重新归入。
- [ ] 设置 › 高级 › 数据安全：立即备份 → 修改一个视频的备注和纳入决定 → 恢复该备份 → 备注和决定回到备份状态。
- [ ] 分析检查器 › 实验方案：选一个预设，结果实时更新，“来源”显示正确；“应用到…”到研究中所有同任务分析。
- [ ] 同一资料库放在共享盘，两台 Mac 先后打开：第二台出现“该资料库正在另一台 Mac 上打开”提示。

## C. 上架（Universal Purchase）

### C1. 上传前清理（避免上传后被自动拒绝）
- [ ] 用 **Xcode 26 或更高版本**归档：自 2026 年 4 月 28 日起，App Store Connect 只接受 Xcode 26（26 SDK）构建的上传。
- [ ] 解压后、打开 Xcode 前，在终端进入本文件夹运行 `sh tools/app_store_preflight.sh`（iPhone 工程：`sh Tools/app_store_preflight.sh`）。它会：
  - 移除所有文件的 `com.apple.quarantine` 扩展属性。从浏览器下载的 zip 解压后每个文件都带着它，Xcode 会把它原样复制进 App（例如模型权重 `weight.bin`），Mac 版上传即被拒：**ITMS-91109: Invalid package contents**；
  - 删除 .DS_Store / ._* / __MACOSX；
  - 检查版本号（Debug 与 Release 一致）、出口合规、Mac 类别、隐私清单、App Sandbox 权限文件。
  全部 ok 再继续；有 FAIL 按提示处理。
- [ ] 工程的最后一个构建阶段 **Remove Extended Attributes** 会在签名前再清一次 App 里的扩展属性；若仍清不掉，构建会报错停下，不会生成会被拒的包。（该阶段需要修改构建出的 App，所以 App target 关闭了 User Script Sandboxing。）
- [ ] Product › Archive（Release 配置，Xcode 默认）。在 Organizer 中右键该归档 › Show in Finder，运行
  `sh tools/app_store_preflight.sh ~/Library/Developer/Xcode/Archives/<日期>/<名称>.xcarchive`
  检查：App 内没有 quarantine（发现会直接清除，然后重新 Distribute 即可）、签名有效、带 App Sandbox 权限、版本 / build 号、隐私清单与两个 .mlmodelc 模型都在 App 内。
- [ ] Organizer › Validate App → Distribute App › App Store Connect。
- [ ] 若提示 build 号已用过：把两个配置的 `CURRENT_PROJECT_VERSION`（Build）改成更大的整数再归档。Mac 的 build 号必须大于该 App 以前上传过的所有 Mac build；iOS 的 build 号在同一版本内不能重复。

### C2. App Store Connect
- [ ] App Store Connect › RodentLimb（现有 iOS 记录）› **Add Platform › macOS**，与 iOS 共用 Bundle ID `com.ziqingshi.rodentlimb`（Universal Purchase）。两个平台都通过审核后，不能再单独移除其中一个平台。
- [ ] 版本号 1.4.2（build 8），iOS 与 Mac 相同；类别与 Info.plist 一致（实用工具 Utilities）。
- [ ] App 隐私：**不收集数据（Data Not Collected）**——App 没有任何网络访问。隐私政策网址（每个 App 都必须填，可以是一页说明“不收集任何数据”的网页）。
- [ ] 年龄分级问卷（2026 年新版问卷）：无相关内容，全部选“无”。
- [ ] 出口合规：Info.plist 已声明 `ITSAppUsesNonExemptEncryption = NO`，App Store Connect 不会再询问。
- [ ] `PrivacyInfo.xcprivacy`：Mac 含 UserDefaults、SystemBootTime、FileTimestamp、DiskSpace；iPhone 含 UserDefaults、SystemBootTime（与代码中实际调用的 API 一一对应）。
- [ ] iPhone：导出的骨架视频可在分享菜单中“存储视频”到照片，Info.plist 已有对应的用途说明（NSPhotoLibraryAddUsageDescription，中英文）。没有这条说明，用户点“存储视频”时 App 会被系统终止。
- [ ] 截图（Mac 1280×800 或 2880×1800；iPhone 6.9″、iPad 13″）：任务页（会话）、任务页（结果）、添加视频、处理队列（有实时画面）、结果复核页。
- [ ] **审核信息 › 附件**：附一段 10–30 秒的小鼠视频（或在备注中给出下载链接）。审核员手里没有动物视频，没有示例很可能以 2.1“无法审核”退回。
- [ ] 审核备注（可直接粘贴）：

```
RodentLimb analyses videos of laboratory mice (gait, cylinder test, tail suspension, scratching and other behaviour scores) with a pose-estimation model that runs on the device. No account, no sign-in, no network access, no data collection.

How to test (Mac):
1. Click "New Task", choose a paradigm (for example "Cylinder test"), then "Create Task".
2. Click "Add Videos…", choose the attached sample video (any short video works to check the workflow), then add it.
3. Tracking starts automatically (sidebar: Processing). When it has finished, open the session in the task to see the results, the review player and the measures. "Export…" writes CSV files.
On iPhone / iPad: Tasks tab › + (New Task), then Add Videos in the task; progress is in the Processing tab.

The Mac app only reads the videos and folders the user chooses or drops (App Sandbox, security-scoped bookmarks). On iPhone, videos are chosen in the Photos or Files picker; nothing is read without the user choosing it.
```

