# RodentLimb (iPhone / iPad) 1.4

On-device limb-pose analysis for **gait**, **cylinder** and **tail suspension** tests, and
behavior scoring for **itch (scratching)**, **spontaneous pain (formalin / capsaicin)**,
**self-grooming** and **seizures (PTZ / kainate)**. Everything runs and stays on the device.
It belongs to the same family as RodentPose and RodentFlow; the library format is the same as
RodentLimb for Mac, so a library can be copied between the two.

中文说明见 `README.zh-Hans.md`.

## Set up (Mac)

```bash
cd ~/Downloads/RodentLimb-iOS
python3 Tools/install_model.py --fp16 ~/Downloads/CylinderPose7_FP16_640.mlpackage.zip
python3 Tools/install_model.py --nir  ~/Downloads/PalmReaderPose8_640_W8A16.mlpackage.zip
open RodentLimb.xcodeproj
```

Both models are already in `RodentLimb/Models/`; the script is only needed to update them. The
project uses a synchronized folder (Xcode 16+), so models and source files are picked up
automatically. Choose your Signing Team, then run on an iPhone or iPad with iOS 17 or later.

### Optional: trained scratch detector

The Itch assay works out of the box with keypoint rules. To use the scratch model trained in
the Colab notebook (`RodentLimb_PublicDatasets_Behavior`, section 9, on Scratch-AID):

```bash
python3 Tools/install_scratch_model.py ~/Downloads/compact_scratch_model.json
```

The script re-scores the file's test vectors (as the app does on load) and copies it to
`RodentLimb/Models/ScratchModel.json`. Rebuild. `--remove` goes back to the rules.

## What's new in 1.4 — task first, then videos

- **Task first** (as in RodentFlow): a task is one paradigm run as one experiment, e.g.
  "Gait — SNI cohort 2". Create the task (choose the paradigm first, then name, groups and
  optional timepoints), then add its videos. Everything is organised as
  task, group, animal, session (timepoint · trial · date).
- **Tabs Tasks · Processing · Settings.** The task screen has one primary action, Add Videos, and
  Sessions | Results | Design, plus Export. Add Videos parses the animal ID, timepoint and trial
  from file and folder names, pre-fills the group when a name contains it, detects duplicates,
  and creates each video's session at once. Needs review, Not in a task (Move to Task…) and All
  videos are listed under Tasks.
- **Pose models**: the 38 MB CylinderMousePoseV2 is removed. Choose per batch between
  **CylinderPose7_FP16_640** (default; visible light; 7 keypoints; the same network in half
  precision) and **PalmReaderPose8_640_W8A16** (near-infrared dark box; 8 keypoints mapped onto the
  stored 7, no mouth). The model of each video is kept in `Recordings/<id>/source.json` (the Mac's
  format) and named in exports and methods; videos without one were tracked with
  CylinderMousePoseV2 and are re-tracked with the FP16 model.
- **Nothing is lost**: Recently Deleted (30 days, Undo right after a delete), daily and
  before-change metadata backups with a restore screen, immediate saves for decisions, deletes,
  imports and task edits, O(1) lookups.
- **Results**: group comparison with every animal as a dot and the group mean ± SEM (Okabe–Ito
  colours, n per group), the course across timepoints, and time courses per group for binned
  measures. Protocol presets in Parameters; parameters and calibration are shared only within a
  task.
- **No decorative icons**: status is short coloured text or a dot, a paradigm is a text chip.
- Legacy data opens unchanged: a 1.3 study with several paradigms shows as one task per paradigm.
- Verification: `sh Tools/core_tests/run_core_tests.sh` compiles the data layer (the real iOS
  store) on macOS or Linux and runs end-to-end tests. The SwiftUI layer was not compiled here.

## What's new in 1.3 — one pipeline: track once → QC → tasks, and study design

The app has one pose model, so every video now goes through it exactly once, is checked, and is
only then analysed by any number of tasks (assays):

1. **Import** videos (Home › +, or from a study). Choose the study, the timepoint and the animal
   ID of each video (suggested from the file name), and optionally the tasks you plan to run.
2. **Process**: the pose model tracks every frame once (background queue, resumes where it
   stopped, as in 1.2.1).
3. **QC**: each video gets a tracking-quality report — share of frames where the mouse (nose +
   tail base) and each keypoint are usable, longest stretch lost, implausible jumps, frame rate —
   with a verdict **Pass / Check / Fail** against criteria set in advance (per study; defaults:
   ≥ 90 % pass, < 70 % fail, ≤ 10 s longest loss, ≥ 25 fps, ≤ 2 % jumps). A timeline shows where
   tracking was lost, and each lost stretch can be jumped to on the video (raw keypoints, no
   gap filling, so you see what the model really found).
4. **Decide**: videos that pass are included automatically; the others wait for an
   **Include / Exclude** decision with a reason (quick reasons provided). Exclusions and their
   reasons are listed per study and exported (ARRIVE 2.0 item 3).
5. **Assign tasks**: planned tasks are created automatically when a video is included; you can
   add tasks to one video or to many at once (Data › Videos › Select). Each task analyses the
   same pose with its own parameters; nothing is re-tracked.

**Studies** (new tab), following common experimental designs and ARRIVE 2.0:
- **Design**: between-subject factors with levels (e.g. Genotype WT/KO × Treatment
  Vehicle/Drug = 4 groups; presets for genotype, treatment, dose, surgery) and within-subject
  timepoints / conditions (e.g. Baseline, Day 7, Day 28). The app names the design (single
  group, between-subject, repeated measures, mixed).
- **Animals** are the experimental unit: ID, **sex** (NIH sex as a biological variable), group
  allocation, cohort / test day (a blocking variable), cage and notes. New IDs typed at import
  are added automatically.
- **Randomisation**: block randomisation stratified by sex (optionally also by cohort), so group
  sizes differ by at most one; animals added later go to the least-filled groups of their
  stratum. The seed and method are written to the study's design text.
- **Blinding**: while on, groups are hidden everywhere (lists, exports, comparisons, design text)
  and animals are shown by random codes — real IDs, cages, notes and video file names are hidden
  too, and the groups cannot be edited — so QC review and include/exclude decisions are made
  blind. Unblind (with a confirmation) when scoring is done.
- **Completeness grid**: animals × timepoints, each cell showing whether the video is included,
  excluded, waiting for review, processing or missing.
- **Group comparison** per task and measure: by groups, by one factor, by sex or groups × sex,
  per timepoint or as a time course (mean ± SEM with individual animals), using included videos
  only. The animal is the unit: repeated trials of one animal at one timepoint are averaged
  first, so n per group counts animals, not videos.
- **Export study**: one long-format CSV per task (one row per video: study, animal, blind code,
  sex, cohort, cage, factors and group, timepoint, trial, QC verdict and coverage, included,
  exclusion reason, then every measure) — ready for two-way / mixed ANOVA or a linear mixed model
  with animal as random effect — plus a design & methods text (design, n per group by sex,
  randomisation, blinding, a-priori QC criteria, exclusions with reasons, gap handling).

**Frames the model could not track** — what is done, following DeepLabCut / SLEAP practice and
the motion-capture gap-filling literature:
- Low-confidence keypoints are treated as missing (confidence threshold, as before).
- Optional **jump rejection**: a keypoint that leaps farther than a threshold (in body lengths)
  from the median of its neighbouring frames is treated as a wrong detection (Hampel filter).
- Only **short gaps** are filled (≤ "fill gaps up to", 0.25 s by default). Methods: **linear**
  (default — the method the analyzers were validated with, so results do not change),
  **shape-preserving cubic**, **body-relative** (the paw's position relative to the body is
  interpolated and carried along with the body, for paws hidden briefly during walking or
  turning) and a **Kalman smoother** (constant velocity, forward–backward).
- **Long gaps are never invented**: they stay missing and are left out of every measure; the QC
  report shows how much was lost and where.
- If a video is poorly tracked, the QC screen exports a **frames-to-label list** (frames where
  the mouse was lost or a keypoint had low confidence, thinned evenly over the whole video) to add to the model's training set and
  retrain (the "extract outlier frames → relabel → retrain" loop), or re-record (lighting,
  contrast, camera angle, ≥ 60 fps for fast behaviours). In-app guidance explains each remedy.

Data from 1.2 is migrated automatically on first launch: each old session becomes a video plus
its analysis, with nothing re-tracked and results unchanged.

## What's new in 1.2.1 — stability (crash fixes)

- **Review player**: jumping to a moment (tapping a chart, an event or a frame button) right after
  opening a session no longer crashes. AVPlayer throws an uncaught exception when it is asked to
  seek before the video is ready; seeks now wait until it is ready (Apple QA1820). A missing or
  damaged video shows a message instead.
- **Pose detection memory**: each frame's Vision / Core ML objects are released inside a per-frame
  autorelease pool, so memory stays flat on long videos instead of growing until iOS terminates
  the app. The skeleton video reuses the writer's pixel-buffer pool.
- **Leaving the app during detection**: detection pauses as soon as the app is no longer active
  (no GPU work is submitted in the background, which iOS forbids) and continues **from the frame
  where it stopped** when you come back, instead of starting the video again. With "render
  skeleton video" on, the video still restarts (AVAssetWriter cannot resume). When the phone gets
  hot, detection slows down instead of overheating.
- **One analysis at a time**: moving parameter sliders, relabeling events, "apply to all" and
  "use calibration for all" queue their analyses; they run one after another (the open session
  first) instead of all at once, which could exhaust memory on long videos.
- **Nothing heavy on the main thread**: the pose track is saved in a compact binary file
  (`pose.bin`, written and read in the background in milliseconds; old `pose.plist` files are
  still read and converted once); importing / copying videos, loading results, exports (including
  the skeleton MP4 copy), group comparison, storage size and the calibration auto-fit all run in
  the background. The frame-by-frame pose CSV is streamed to disk.
- **Saving**: disk writes run in order on one background queue and are given time to finish when
  the app is sent to the background. Measures that are NaN or infinite no longer prevent a
  session or result from being saved.
- **Robustness**: damaged pose files are repaired on load (arrays of different lengths), every
  frame-count / bin conversion in the analyzers is guarded against NaN, infinite or huge values,
  and degenerate calibrations are treated as missing. Caches are trimmed on memory warnings.
- **Smoothness**: the playback line on the ethogram is drawn on its own layer (the chart is no
  longer rebuilt during playback), long event lists are lazy, footprints are drawn with Canvas,
  and interface strings no longer re-read the language preference each time.

## What's new in 1.2 — behavior scoring

Four new assays, designed around how each field scores and reports these behaviors. All four
share the same result layout: key numbers, an **ethogram**, a **time course in bins from the
injection**, the detection signal, and a **review list** where every automatic event can be
played and relabeled (edits are kept and every measure updates). Exports add `_events.csv`,
`_time_bins.csv`, `_ethogram.csv` and a methods paragraph with references.

| Assay | Field convention followed | Measures |
|---|---|---|
| **Itch** (scratching) | Bout = hind-paw strokes until the paw returns to the floor or pauses (Kuraishi 1995; Valtcheva 2015). 30 min from the injection, 5-min bins. Cheek model: hind-paw scratching = itch, unilateral forepaw wiping = pain (Shimada & LaMotte 2008; Yamanoi 2019) | Bouts, scratching time and %, latency, bouts/min, mean and longest bout, **trains** (bouts < 2 s apart; Scratch-AID), left/right hind paw and side index. Cheek model: wipes, wiping time, left/right |
| **Spontaneous pain** | Licking/biting = any mouth contact with the injected paw (Wotton 2020). Phase I 0–10 min, phase II 10–60 min (Mogil 1999), 5-min bins; all adjustable | Licking time in phase I, interphase and phase II, bouts, latency, flinches per phase, **contralateral-paw licking** (grooming control) and ipsilateral share |
| **Self-grooming** | Cephalo-caudal regions: face → body → hind leg → tail/genitals. A pause > 5 s ends a bout; shorter pauses = interrupted bout (Estanislau 2012). Microstructure (Kalueff & Tuohimaa 2004/2005) | Time, %, bouts, latency, mean and longest bout, time per region, **% interrupted bouts**, **% incorrect (non head-to-tail) transitions**; hind-paw scratching is excluded and reported separately |
| **Seizure scoring** | Revised Racine scale for PTZ in mice (Van Erum 2019, stages 1–7) or modified Racine for kainate / pilocarpine (1–5; Sharma 2018). Clonus ≥ 3 s (NINDS s.c. PTZ endpoint). Baseline before injection = false-positive check | Maximal stage, **latency to first myoclonic jerk**, to first generalized seizure, to convulsions on the side and to tonic extension, time to maximal stage, jerk / clonic / convulsion counts, seizure time, episodes, suspected death after tonic extension, baseline detections |

What the app detects from the bottom view, and how:

- **Scratching**: high-frequency hind-paw energy (the same features as the trained model,
  ported exactly from the notebook) well above the video's own keypoint jitter, the paw near the
  head, the body still. With `ScratchModel.json` installed, the model scores every frame and
  its tuned post-processing is applied.
- **Licking**: mouth within 0.30 BL of the injected paw while the body is still.
  **Flinches**: a ~0.1-s speed spike of that paw (measured over ~33 ms so 30 and 60 fps behave
  the same; the threshold rises automatically on noisy tracks) with the body still for ±0.3 s.
- **Grooming regions**: both forepaws stroking at the mouth (face), head turned to the flank
  and moving (body), mouth at a hind paw (leg), nose at the tail base (tail).
- **Seizure events**: myoclonic jerks (most keypoints twitch together and the mouse stays in
  place), clonus (rhythmic fore- and hind-limb movement, body in place, ≥ 3 s), convulsions on
  the side (all paws on one side of the body axis), wild running/jumping, tonic hindlimb
  extension (both hind paws behind the tail base). Behavioral arrest (stage 1) is off by
  default because, from below, it looks like an ordinary pause.

Parameters are per assay (injection time in the video, window, bins, phases, injected paw,
scale, thresholds). "Apply to all" keeps each video's own injection time.

The literature behind these choices (definitions, windows, scales, with each point marked as
verified or not) is in `Docs/behavior_scoring_conventions.md`.

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

1. **New Task** (Tasks › +): choose the paradigm, then name, groups (optional) and timepoints.
2. **Add Videos** inside the task: Files (files or a folder), Photos, or drop on iPad. Each video
   gets an animal ID, group, timepoint and trial (suggested from file and folder names) and
   becomes a session of the task at once. The pose model is chosen once per batch.
3. **Processing** runs the pose model once per video in a background queue, one video at a time
   (Processing tab). If you leave the app, tracking pauses and continues from the same frame.
4. **QC and inclusion.** A video that meets the task's criteria is included automatically; the
   others wait in Needs review and are included, or excluded with a reason. Excluded sessions
   stay visible in the task, marked, and are left out of the group results.
5. **Calibration** only for cylinder (rim or floor line) and gait (optional cm ruler); "Auto"
   proposes a position from the tracking, and one calibration can be used for every session of
   the task.
6. **Results** are recomputed instantly when you move a parameter slider; the model is never
   re-run. The session screen has Summary · Review · Measures; the task screen compares the
   groups.
7. **Export** a task (summary, QC with pose model, events, time bins, methods and design, README,
   manifest) or a single session (summary, events or strides, frame-by-frame pose CSV, methods).
   Always in English.

## What is measured

| Assay | Measures |
|---|---|
| Tail suspension | Immobility time and %, analyzed over minutes 2–6 by default; latency; bout count, mean and longest bout; per-minute profile; tail climbing %; estimated hindlimb clasping score 0–3 with per-limb %; hind paw separation |
| Cylinder | Left, right and both counts. With a lesion side set: contralateral use %, contralateral including ½ both, and asymmetry index. Also rears, contact time per paw, and time to 20 contacts. Every event can be reviewed on the video and relabeled; edits persist |
| Gait | Speed and its CV; stride length (fore and hind); stride frequency; stance, swing and duty factor; base of support; print position; interlimb phase (LH→RH, LF→RF, LH→LF, LH→RF) with circular R; regularity index; L−R asymmetry. Charts: footfall diagram, per-paw table, phase dials, footprint map |
| Itch / pain / grooming / seizure | See *What's new in 1.2* above |

All thresholds are in body lengths (median nose–tail-base distance), so they carry over between
cameras. The Settings › Methods pages give each definition and its reference.

## Validation done here

- **1.3**: this environment has no Swift compiler, so the new code was syntax-checked and
  reviewed line by line against every declaration it uses, but **not compiled** — build once in
  Xcode and send me any errors. The gap-filling methods, jump rejection, the QC indexing and the
  randomiser were ported to Python and tested: interior gaps up to the max gap are filled with
  finite values and long gaps or gaps at the ends stay missing for every method; linear fill is
  identical to 1.2; the cubic fill never overshoots; body-relative fill is exact for a rigidly
  turning body (linear: 2.3 px error); the Kalman smoother is exact on straight-line motion;
  jump rejection removed exactly 17/17 injected outliers with no false positives and keeps fast
  paws (up to 10 BL/s) next to gaps; over 300 random designs every sex (× cohort) stratum is
  balanced within one animal, also when animals are added later.

- **1.2 (behavior assays)**: the whole analysis layer (Foundation only) compiles with Swift
  5.10 and was run on simulated bottom-view keypoint tracks with known ground truth
  (`Tools/validation/behavior/run.sh`; add `--sweep` for 20 runs: 5 seeds × keypoint noise
  0.8 % / 1.5 % BL × 30 / 60 fps). Over the 20 runs:
  - scratching bouts 240/240 found, 0 false; cheek-model scratches 160/160 and wipes 160/160
  - licking of the injected paw 320/320; flinches 440/440, 0 false
  - myoclonic jerks 100/100, 0 false; clonic, side-lying, wild running and tonic extension
    found in every run; maximal stage 7 in every run; 0 baseline false positives
  - grooming: 6/6 bouts every run; total time −2 to −5 % at 0.8 % noise, −9 to −16 % at 1.5 %
  - negative control (5 min of exploration, rest and face/body grooming, ×20): 0 scratching,
    0 wiping, 0 licking, 0 flinch and 0 seizure detections
  The simulator cannot stand in for real video: thresholds still need checking on your own
  recordings, which is why every event is reviewable.
- The feature code used by the trained scratch model is an exact port of the notebook
  (`_features_core`): 96 features matched the Python output to ~1e-7 relative error, and
  probabilities and bouts were identical at 30 and 60 fps.
- UI files were syntax-checked (`swiftc -parse`) but **not** compiled with the iOS SDK,
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

- **Behavior assays (1.2)** have not been validated against human scoring of real videos, so
  treat the defaults as a starting point. Score a few videos by hand, compare, and adjust the
  parameters (then "Apply to all"). From below, the scratching paw's contact with the nape or
  cheek, facial jerks (PTZ stage 2), whisker trembling and lying on the belly cannot be seen
  directly; the app says so in its notes. Scratching at 20 Hz is faster than 30 fps, so record
  at ≥ 60 fps when possible.

- The visible-light network was trained on **cylinder** video. Tail suspension and gait videos are a different view, so
  keypoints may be less accurate. Each result shows pose coverage and warns when it is low.
  Check the overlay in the review player. If paw tracking is weak, add labeled frames from those
  setups to the training set.
- The clasping score is an automated estimate. Confirm it visually.
- Gait measures depend on speed. Compare groups at matched speeds or use speed as a covariate;
  per-stride speed is in the export.
