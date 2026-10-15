# RodentLimb

On-device limb-pose analysis for **tail suspension**, **cylinder** and **gait** tests, built on
**CylinderMousePoseV2** (7 keypoints: L/R fore paws, L/R hind paws, tail base, nose, mouth).
It belongs to the same family as RodentPose and RodentFlow: same blue accent, card layout and
Okabe–Ito data colors. Paw colors match the app icon.

中文说明见 `README.zh-Hans.md`.

**User manual (English / 中文): https://seesaw-earth.github.io/RodentLimb/** ·
[Privacy policy](https://seesaw-earth.github.io/RodentLimb/privacy.html) ·
[Support](https://seesaw-earth.github.io/RodentLimb/support.html) ·
License: GNU AGPL-3.0 (see `THIRD_PARTY_NOTICES.md`, `MODEL_PROVENANCE.md`)

## Set up (Mac)

```bash
cd ~/Downloads/RodentLimb
python3 Tools/install_model.py --v2 ~/Downloads/CylinderMousePoseV2.mlpackage.zip
open RodentLimb.xcodeproj
```

`--v2` also accepts the copy already installed in the A/B project:
`~/Downloads/CylinderPose_DualModel_AB/CylinderPose/CylinderPose/Models/CylinderMousePoseV2.mlpackage`.
The project uses a synchronized folder (Xcode 16+), so the model and every source file are
picked up automatically. Do not drag the model in again. Choose your Signing Team, then run on
an iPhone with iOS 17 or later.


## What's new in 1.1.2 (smoothness)

- **Review scrubbing**: picture and keypoints now move together. Seeks use Apple's chase-seek
  pattern (QA1820): only the newest target is sought, and keypoints are drawn for the frame
  actually on screen. You can also swipe sideways on the video to step frame by frame (6 pt per
  frame). The frame buttons give a light haptic tick.
- **No more whole-screen redraws**: processing progress (throttled to 4 Hz) and the playback
  clock now only refresh the small views that show them, not the screens around them (charts,
  forms).
- **Background disk writes**: session saves are coalesced and written off the main thread.
  Parameter sliders redraw only the form and re-analyze once you pause. The large pose CSV
  export is built in the background.
- **Typing**: Return moves to the next field; the number pad has a Done key; dragging dismisses
  the keyboard; the bottom button hides while typing.

## What's new in 1.1

- **Icon and colors**: new mascot icon. Paw colors now match it: LF blue, RF red, LH green,
  RH violet, tail pink.
- **Simpler screens**:
  - Home has a single "New analysis" button, three assay tiles, and Recent.
  - Each result has three tabs: **Summary** (the 2–4 key numbers, notes and one chart),
    **Review** (video with keypoints, plus the events behind the numbers) and **Measures**
    (every measure in labelled groups, plus detailed charts).
  - The Data tab is a native list: swipe to delete, Select for batch export.
  - A short welcome tour runs on first launch.
- **iOS 26 / Liquid Glass**: bottom bars use the system scroll-edge effect instead of custom
  backgrounds; the main button uses `.glassProminent`; the tab bar shrinks while scrolling;
  rounded type is used throughout. Earlier iOS versions fall back automatically.
- **Gait methods v2** (Sheppard et al. 2022; Bellardita & Kiehn 2015; Batka et al. 2014):
  - Strides are kept only when the mouse walks in a straight line (|angular velocity| ≤ 30 °/s
    by default). The first and last stride of each run are dropped (acceleration).
  - **Speed-matched values**: each animal's stride-vs-speed fit is read at a common reference
    speed (2 BL/s). Values are left blank rather than extrapolated when the animal never walked
    near that speed.
  - Stride variability (CV), step length, and stride length in body lengths.
  - Gait pattern per stride (walk / trot / gallop / bound).
  - Nose and tail-base lateral sway (amplitude and phase) as a whole-body coordination measure.
  - Validated against simulated mice (`Tools/validation/test3.py`):
    - step length 25.6 px (true 25)
    - nose sway 0.129 BL (true 0.133)
    - speed-matched stride length 50.2 px (true 50.0)
    - turning strides correctly rejected; trot classified correctly
- Results saved by 1.0 are recomputed automatically the first time they are opened.

## How it works

1. **New analysis.** Pick an assay, then select one or many videos (Photos or Files). Subject
   IDs default to the file names.
2. **Pose detection** runs once per video in a background queue, one video at a time. The
   screen stays awake. If you leave the app, detection pauses and then resumes automatically.
3. **Calibration** is only needed for some assays. Cylinder needs the rim (bottom view) or the
   floor line (side view). Gait can use an optional cm ruler. "Auto" proposes a position from
   the tracking. A loupe helps with precise placement. One calibration can be reused for every
   video from a fixed camera.
4. **Results** are recomputed instantly when you move a parameter slider; the model is never
   re-run. The review player draws keypoints live, with frame stepping and 0.25–4× playback.
5. **Exports** are always in English: summary, events or strides, frame-by-frame pose CSV, and
   a methods paragraph with your parameter values and references. The Data tab exports one
   wide CSV per assay, one row per animal, and shows a quick group comparison.

## What is measured

| Assay | Measures |
|---|---|
| Tail suspension | Immobility time and %, analyzed over minutes 2–6 by default; latency; bout count, mean and longest bout; per-minute profile; tail climbing %; estimated hindlimb clasping score 0–3 with per-limb %; hind paw separation |
| Cylinder | Left, right and both counts. With a lesion side set: contralateral use %, contralateral including ½ both, and asymmetry index. Also rears, contact time per paw, and time to 20 contacts. Every event can be reviewed on the video and relabeled; edits persist |
| Gait | Speed and its CV; stride length (fore and hind); stride frequency; stance, swing and duty factor; base of support; print position; interlimb phase (LH→RH, LF→RF, LH→LF, LH→RF) with circular R; regularity index; L−R asymmetry. Charts: footfall diagram, per-paw table, phase dials, footprint map |

All thresholds are in body lengths (median nose–tail-base distance), so they carry over between
cameras. The Settings › Methods pages give each definition and its reference.

## Validation done here

- All Swift files parse cleanly (tree-sitter). They have **not** been compiled with the iOS SDK,
  because this environment has no Xcode. Build once in Xcode and send me any errors.
- The three analyzers were ported line-for-line to Python and run on simulated mice with known
  ground truth:
  - **Gait** (trot at 100 fps, 1.5 px noise): stride length, frequency, base of support and
    phases were exact; duty factor was 0.59 against a true 0.60. At 30 fps, duty has about 1
    frame of bias, and the app warns about this.
  - **Tail suspension**: 163.5 s immobility against 165.4 s true; 99.2 % frame agreement.
  - **Cylinder**: 9/9 rears labeled correctly, even with 3 px noise and 20 % paw dropouts.
- The defaults were tuned from these tests. Stance speed ratio is 0.8 and gait smoothing is
  0.03 s. Stance uses the smaller of the backward and forward steps, so touch-down and lift-off
  frames are not lost.

## Limitations

- V2 was trained on **cylinder** video. Tail suspension and gait videos are a different view, so
  keypoints may be less accurate. Each result shows pose coverage and warns when it is low.
  Check the overlay in the review player. If paw tracking is weak, add labeled frames from those
  setups to the V2 training set.
- The clasping score is an automated estimate. Confirm it visually.
- Gait measures depend on speed. Compare groups at matched speeds or use speed as a covariate;
  per-stride speed is in the export.
