# RodentLimb

Limb pose and behavior scoring for mouse videos, on Mac, iPhone and iPad. A pose model tracks the
four paws, nose, mouth and tail base in every frame, on the device; seven tests are scored from the
keypoints: tail suspension, cylinder, gait, itch (scratching), spontaneous pain, self-grooming and
seizures. No account, no network connection, nothing uploaded.

- Website and user manual (English / 中文): https://seesaw-earth.github.io/RodentLimb/
- App Store (Mac, iPhone and iPad, one purchase): https://apps.apple.com/app/id6822935387
- 中文说明：[README.zh-Hans.md](README.zh-Hans.md)

Version in this repository: **1.4.2 (build 8)** for both apps.

## What is where

| Folder | Contents |
|---|---|
| `RodentLimb/`, `RodentLimb.xcodeproj` | iPhone and iPad app (iOS 17+) |
| `Mac/macOS/` | Mac app (macOS 14+): `RodentLimb.xcodeproj` and its sources |
| `Mac/Shared/` | Analysis layer used by both apps: pose cleaning, the seven analyzers, QC, study design, export, methods text. Byte-identical to the same files in `RodentLimb/` (`sh Mac/tools/verify_shared.sh RodentLimb` checks it) |
| `Tools/`, `Mac/tools/` | Model installers, command-line tests, App Store pre-flight checks, validation scripts |
| `docs/` | Website and manual (VitePress; the home pages are `docs/public/index.html` and `docs/public/zh/index.html`) |
| `tools/homepage/` | Turns screen recordings into the clips on the home page |
| `dev-notes/` | Design notes and work logs |
| `AppStore/` | Store texts and App Review notes |

## Build

You need Xcode 26 or later (required for App Store uploads since April 2026). There are no
third-party packages; both projects use synchronized folders, so new files are picked up
automatically.

The pose-model weights are not in this repository (see `MODEL_PROVENANCE.md`). Install them first:

```bash
# iPhone / iPad
python3 Tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
# Mac
python3 Mac/tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
```

Without them the apps build and open, and report that the model is missing when a video is tracked.

Then open `RodentLimb.xcodeproj` (iPhone) or `Mac/macOS/RodentLimb.xcodeproj` (Mac), choose your
signing team and run.

## Tests

```bash
sh Tools/core_tests/run_core_tests.sh       # iPhone analysis layer
sh Mac/tools/run_core_tests.sh              # Mac analysis layer and library
sh Mac/tools/verify_shared.sh RodentLimb    # the shared files are identical in both apps
```

## Before an App Store upload

```bash
sh Tools/app_store_preflight.sh             # iPhone project
sh Mac/tools/app_store_preflight.sh         # Mac project
```

The script removes the `com.apple.quarantine` attribute that files unpacked from a download carry
(App Store Connect rejects a Mac app containing such a file, ITMS-91109), and checks versions,
Info.plist keys, the privacy manifest and the sandbox. Run it again on the `.xcarchive` after
archiving. The full checklist is in `Mac/RELEASE_CHECKLIST_CN.md`.

## Website

```bash
npm ci
npm run docs:dev        # local preview
```

Pushing changes under `docs/` to `main` publishes the site with GitHub Actions. Home-page clips:
`tools/homepage/encode-all.sh` (see the comments in the script).

## Cite

> Shi, Z. (2026). *RodentLimb* (Version 1.4.2) [Computer software]. https://seesaw-earth.github.io/RodentLimb/

See `CITATION.cff` and https://seesaw-earth.github.io/RodentLimb/models/cite.html for the models
and their training data.

## License

GNU AGPL-3.0 (`LICENSE`). Third-party notices: `THIRD_PARTY_NOTICES.md`.
