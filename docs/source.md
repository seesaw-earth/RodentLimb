# Open source & building

RodentLimb is open source under the **[GNU AGPL-3.0](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)**. The app, every analysis and this manual are in one public repository:

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## Where things are in the code

| Topic | Manual page | Source file |
|---|---|---|
| Pose inference, decoding, video reading | [Pose model](./principles/pose.md) | [`PoseEngine.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Pose/PoseEngine.swift), [`PoseDecoder.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Pose/PoseDecoder.swift) |
| Cleaning, body length, signal tools | [Pose model](./principles/pose.md#cleaning) | [`PoseSeries.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/PoseSeries.swift) |
| Tail suspension | [Tail suspension](./assays/tail-suspension.md) | [`TSTAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/TSTAnalyzer.swift) |
| Cylinder test | [Cylinder test](./assays/cylinder.md) | [`CylinderAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/CylinderAnalyzer.swift) |
| Gait | [Gait analysis](./assays/gait.md) | [`GaitAnalyzer.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/GaitAnalyzer.swift) |
| Parameters and defaults | [Parameters](./guide/parameters.md) | [`AnalysisModels.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Analysis/AnalysisModels.swift) |
| Exports and methods text | [Files & exports](./reference/files.md) | [`Exporter.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/Data/Exporter.swift) |
| Validation scripts | [Validation](./principles/validation.md) | [`Tools/validation/`](https://github.com/seesaw-earth/RodentLimb/tree/main/Tools/validation) |
| English and Chinese text | — | `L("English", "中文")` calls in every view; [`L10n.swift`](https://github.com/seesaw-earth/RodentLimb/blob/main/RodentLimb/App/L10n.swift) |

## Build from source

You need a Mac with **Xcode 16 or later** and an iPhone with **iOS 17 or later**. There are no third-party Swift packages.

```bash
git clone https://github.com/seesaw-earth/RodentLimb.git
cd RodentLimb
python3 Tools/install_model.py --v2 /path/to/CylinderMousePoseV2.mlpackage.zip
open RodentLimb.xcodeproj
```

In Xcode, choose your signing team and run on an iPhone. The model weights are **not** in the repository; see `MODEL_PROVENANCE.md`.

## Build this manual

```bash
npm install
npm run docs:dev     # live preview at http://localhost:5173/RodentLimb/
npm run docs:build   # static site in docs/.vitepress/dist
```

Pushing changes under `docs/` to `main` publishes the site through GitHub Actions.
