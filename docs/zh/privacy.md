---
outline: false
---

# 隐私政策

*最后更新：2026 年 11 月 · 适用于 RodentLimb for Mac、iPhone 和 iPad*

**简而言之：RodentLimb 不收集、不传输、不分享任何数据。你在 App 中的一切操作都留在你的 Mac 或设备上。**

## App 处理什么

RodentLimb **只在你的 Mac 或设备上**处理：

- 你选择分析的视频；
- 你输入的研究信息，例如动物编号、分组、性别、时间点和备注；
- App 由此计算出的关键点、质控、结果、图表和文件；
- 你的设置，例如界面语言。

## App 不做什么

- **没有网络功能。** 不向开发者或任何服务器上传、同步或发送任何内容。Mac 版完全不申请网络访问权限。
- **没有账号**、登录或注册。
- **不包含统计分析、广告、崩溃报告或跟踪**代码，也没有第三方 SDK。
- **不**访问你的通讯录、位置、麦克风或健康数据。

## 你可以自行核实

RodentLimb 是开源的，完整源代码公开在 [github.com/seesaw-earth/RodentLimb](https://github.com/seesaw-earth/RodentLimb)。App 内附带的隐私清单（`PrivacyInfo.xcprivacy`）声明不跟踪、不收集数据。Mac 版在 macOS App 沙盒中运行。

## 在 Mac 上

- **文件和文件夹。** Mac 版只能读取你在打开面板中选择或拖进窗口的视频和文件夹，以及你选择的资料库文件夹。它通过安全范围书签保留访问权限，因此视频可以留在原处。
- **数据存放位置。** 在资料库中：默认在 App 容器内（`Documents/RodentLimb`），或在你选择的文件夹中。备份和最近删除的项目也保存在资料库内。
- **资料库锁。** 打开资料库期间，其中的 `.rodentlimb-lock.json` 文件记录 Mac 的名称和你的 macOS 用户名，以便第二台 Mac 打开同一资料库（例如在共享盘上）时提醒你。它不会被发送到任何地方；能打开该文件夹的人可以看到它。
- **通知。** 如果你允许通知，批处理完成时 macOS 会显示一条通知。通知在你的 Mac 上生成。

## 在 iPhone 和 iPad 上

- **照片。** 通过系统照片选择器选择视频。RodentLimb 只收到你选择的视频，无法访问照片图库的其余部分。
- **文件。** 在“文件”选择器中选择的文件只在选择时读取。App 把视频复制到自己的文件夹：*文件 › 我的 iPhone › RodentLimb*。

## 备份与分享

你的数据会按你自己的备份设置包含在 Mac 或设备的备份中（时间机器、iCloud 或电脑），这些备份由 Apple 管理。如果把资料库放在共享盘或云盘上，则适用该服务的条款。只有当**你**导出或分享数据时，数据才会离开你的 Mac 或设备，并且只发送到你选择的目的地。

## 删除数据

在 App 中删除视频、分析或研究（在 Mac 上它们会进入“最近删除”保留 30 天，你也可以在那里立即清除），删除资料库文件夹，或删除 App 以清除其容器中的数据。

## 本网站

本手册托管在 GitHub Pages 上。出于安全原因，GitHub 可能会记录访问者的 IP 地址；见 [GitHub 隐私声明](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)。本网站不设置 Cookie，也不使用自己的统计分析。

## 儿童

RodentLimb 是供研究实验室使用的工具，不收集任何人（包括儿童）的数据。

## 变更

如本政策有变更，新版本将在本页发布并更新日期。任何引入数据收集的变更都会在生效之前在本页和更新说明中明确说明。

## 联系

关于本政策的问题：在 [github.com/seesaw-earth/RodentLimb/issues](https://github.com/seesaw-earth/RodentLimb/issues) 提交 issue，或见[支持](./support.md)。

开发者：Ziqing Shi
