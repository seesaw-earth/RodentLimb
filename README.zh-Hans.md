# RodentLimb

在 Mac、iPhone 和 iPad 上完成小鼠视频的肢体姿态识别与行为评分。姿态模型在本机逐帧识别四只爪、鼻、口和尾根，再据此评分七种实验：悬尾、圆筒、步态、瘙痒（抓挠）、自发痛、自我理毛和癫痫发作。无需账号，不联网，不上传任何数据。

- 网站与使用手册（中文 / English）：https://seesaw-earth.github.io/RodentLimb/zh/
- App Store（Mac、iPhone、iPad 一次购买）：https://apps.apple.com/app/id6822935387
- English: [README.md](README.md)

本仓库版本：两个 App 均为 **1.4.2（build 8）**。

## 目录

| 文件夹 | 内容 |
|---|---|
| `RodentLimb/`、`RodentLimb.xcodeproj` | iPhone / iPad 版（iOS 17+） |
| `Mac/macOS/` | Mac 版（macOS 14+）：`RodentLimb.xcodeproj` 及源代码 |
| `Mac/Shared/` | 两个 App 共用的分析层：姿态预处理、七个分析器、QC、实验设计、导出与方法学文字。与 `RodentLimb/` 中的同名文件逐字节相同（`sh Mac/tools/verify_shared.sh RodentLimb` 检查） |
| `Tools/`、`Mac/tools/` | 模型安装、命令行测试、上架前检查、验证脚本 |
| `docs/` | 网站与手册（VitePress；首页是 `docs/public/index.html` 与 `docs/public/zh/index.html`） |
| `tools/homepage/` | 把录屏转成首页视频 |
| `dev-notes/` | 设计说明与开发记录 |
| `AppStore/` | 商店文字与审核备注 |

## 编译

需要 Xcode 26 或更高版本（2026 年 4 月起上传 App Store 必须）。没有第三方依赖；两个工程都使用同步文件夹，新文件自动加入。

姿态模型权重不在仓库中（见 `MODEL_PROVENANCE.md`），先安装：

```bash
# iPhone / iPad
python3 Tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
# Mac
python3 Mac/tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
```

不安装也能编译和打开，识别视频时会提示缺少模型。然后打开 `RodentLimb.xcodeproj`（iPhone）或 `Mac/macOS/RodentLimb.xcodeproj`（Mac），选择签名团队并运行。

## 测试

```bash
sh Tools/core_tests/run_core_tests.sh       # iPhone 分析层
sh Mac/tools/run_core_tests.sh              # Mac 分析层与资料库
sh Mac/tools/verify_shared.sh RodentLimb    # 两个 App 的共用文件完全一致
```

## 上传 App Store 之前

```bash
sh Tools/app_store_preflight.sh             # iPhone 工程
sh Mac/tools/app_store_preflight.sh         # Mac 工程
```

脚本会移除下载解压后文件带有的 `com.apple.quarantine` 属性（Mac App 中有这种文件会被 App Store Connect 拒绝，ITMS-91109），并检查版本号、Info.plist、隐私清单和沙盒。归档后再对 `.xcarchive` 运行一次。完整清单见 `Mac/RELEASE_CHECKLIST_CN.md`。

## 网站

```bash
npm ci
npm run docs:dev        # 本地预览
```

`docs/` 下的改动推送到 `main` 后由 GitHub Actions 自动发布。首页视频：`tools/homepage/encode-all.sh`（说明见脚本注释）。

## 引用

> Shi, Z. (2026). *RodentLimb* (Version 1.4.2) [Computer software]. https://seesaw-earth.github.io/RodentLimb/

模型及其训练数据的引用见 `CITATION.cff` 和 https://seesaw-earth.github.io/RodentLimb/zh/models/cite.html 。

## 许可

GNU AGPL-3.0（`LICENSE`）。第三方声明：`THIRD_PARTY_NOTICES.md`。
