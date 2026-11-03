# Open source & building

RodentLimb is open source under the **[GNU AGPL-3.0](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)**. The app, the analyses and this manual are in one public repository:

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## How the code is organized

The iPhone and Mac apps share one analysis layer, so a video gives the same keypoints and the same measures on both.

| Part | Folder | What it does |
|---|---|---|
| **Shared analysis** | `Mac/Shared/` (the same files are in `RodentLimb/`) | Keypoint cleaning, the seven analyzers, QC, study design, export and the methods text. Foundation only, so it also compiles and is tested on the command line |
| **iPhone app** | `RodentLimb/`, `RodentLimb.xcodeproj` | Importing on the phone, Core ML tracking, the iPhone and iPad interface |
| **Mac app** | `Mac/macOS/` | Library, batch engine with checkpoints, Core ML + Vision tracking, the Mac interface |
| **Pose models** | not in the repository | See [Pose models](./models/); installed into each project with `install_model.py` |
| **This website** | `docs/` | VitePress manual; the home pages are `docs/public/index.html` and `docs/public/zh/index.html` |

## Where things are in the code

| Topic | Manual page | Source file |
|---|---|---|
| Pose inference and decoding | [Pose estimation & cleaning](./principles/pose.md) | `PoseRunner.swift` (Mac), `PoseEngine.swift` (iPhone), `PoseDecoder.swift` |
| Cleaning, gap filling, body length | [Pose estimation & cleaning](./principles/pose.md#cleaning) | `PoseSeries.swift`, `GapRepair.swift` |
| Tail suspension | [Tail suspension](./assays/tail-suspension.md) | `TSTAnalyzer.swift` |
| Cylinder test | [Cylinder test](./assays/cylinder.md) | `CylinderAnalyzer.swift` |
| Gait | [Gait analysis](./assays/gait.md) | `GaitAnalyzer.swift` |
| Itch | [Itch](./assays/itch.md) | `ItchAnalyzer.swift`, `ScratchModel.swift` |
| Spontaneous pain | [Spontaneous pain](./assays/pain.md) | `PainAnalyzer.swift` |
| Self-grooming | [Self-grooming](./assays/grooming.md) | `GroomingAnalyzer.swift` |
| Seizure | [Seizure scoring](./assays/seizure.md) | `SeizureAnalyzer.swift` |
| Quality control | [Quality control](./guide/qc.md) | `QualityControl.swift` |
| Parameters, defaults, presets | [Parameters](./guide/parameters.md) | `AnalysisModels.swift`, `ParameterPresets.swift` |
| Exports and methods text | [Export](./guide/export.md) | `Exporter.swift`, `StudyExport.swift` |
| Validation scripts | [Validation](./principles/validation.md) | [`Tools/validation/`](https://github.com/seesaw-earth/RodentLimb/tree/main/Tools/validation) |
| English and Chinese text | — | `L("English", "中文")` calls in every view; `L10n.swift` |

::: info Version in the repository
The repository holds the 1.4.2 source of both apps. The release notes of each version are in the [changelog](./reference/changelog.md).
:::

## Build from source

You need **Xcode 26 or later**. There are no third-party Swift packages.

- **Mac**: macOS 14 or later. Open `Mac/macOS/RodentLimb.xcodeproj`, choose your signing team and run. The project uses synchronized folders, so new files are picked up automatically.
- **iPhone**: an iPhone or iPad with iOS 17 or later. Open `RodentLimb.xcodeproj` at the top of the repository.

The model weights are not in the repository. Install them into the project before building, for example:

```bash
# iPhone and iPad
python3 Tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
# Mac
python3 Mac/tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
```

Where the weights come from and how they were trained is on the [model pages](./models/).

## Tests

```bash
sh Tools/core_tests/run_core_tests.sh      # iPhone analysis layer
sh Mac/tools/run_core_tests.sh             # Mac analysis layer and library
sh Mac/tools/verify_shared.sh RodentLimb   # the shared files are identical in both apps
```

## Build this manual

```bash
npm install
npm run docs:dev     # live preview at http://localhost:5173/RodentLimb/
npm run docs:build   # static site in docs/.vitepress/dist
```

Pushing changes under `docs/` to `main` publishes the site through GitHub Actions.
