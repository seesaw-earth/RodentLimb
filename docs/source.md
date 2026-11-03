# Open source & building

RodentLimb is open source under the **[GNU AGPL-3.0](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)**. The app, the analyses and this manual are in one public repository:

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## How the code is organized

The iPhone and Mac apps share one analysis layer, so a video gives the same keypoints and the same measures on both.

| Part | What it does |
|---|---|
| **Shared analysis** | Keypoint cleaning, the seven analyzers, QC, study design, export and the methods text. Foundation only, so it also compiles and is tested on the command line |
| **iPhone app** | Recording and importing on the phone, Core ML tracking, the iPhone interface |
| **Mac app** | Library, batch engine with checkpoints, Core ML + Vision tracking, the Mac interface |
| **Pose models** | Not in the repository (see [Pose models](./models/)); installed into the project with `install_model.py` |
| **This manual** | VitePress site in `docs/`, published with GitHub Pages |

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
The repository is being updated to the 1.3.5 source of both apps. Until that is complete, it may hold an earlier version; the release notes of each version are in the [changelog](./reference/changelog.md).
:::

## Build from source

You need **Xcode 16 or later**. There are no third-party Swift packages.

- **Mac**: macOS 14 or later. Open the Mac project, choose your signing team and run. The project uses synchronized folders, so new files are picked up automatically.
- **iPhone**: an iPhone or iPad with iOS 17 or later.

The model weights are not in the repository. Install them into the project before building, for example:

```bash
python3 tools/install_model.py --fp16 /path/to/CylinderPose7_FP16_640.mlpackage.zip   # visible light
python3 tools/install_model.py --nir  /path/to/PalmReaderPose8_640_W8A16.mlpackage.zip # near-infrared
```

Where the weights come from and how they were trained is on the [model pages](./models/).

## Build this manual

```bash
npm install
npm run docs:dev     # live preview at http://localhost:5173/RodentLimb/
npm run docs:build   # static site in docs/.vitepress/dist
```

Pushing changes under `docs/` to `main` publishes the site through GitHub Actions.
