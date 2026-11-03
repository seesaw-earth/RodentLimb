# RodentLimb 1.4 — task-first design (iPhone/iPad and Mac)

Owner request (Chinese, paraphrased): remove the 38 MB model; remove superfluous emoji-like icons;
follow the earlier design referencing RodentFlow build 11 — **choose the task first, then process
videos**; data and grouping follow the same flow; make the iOS app smooth, never lose data, friendly,
with beautiful visualisation; every app simple, intuitive and well organised.

## 1. Concepts (no change to the shared file formats)

| User sees | Stored as | Notes |
|---|---|---|
| **Task** (任务) — one paradigm run as one experiment, e.g. "Gait — SNI cohort 2" | `Experiment` whose `plannedAssays == [assay]` (exactly one) | name, notes, groups, animals, timepoints, QC criteria, blinding all already exist on `Experiment` |
| **Group** (组) | levels of the experiment's single factor named "Group" (`factors[0]`), `Animal.levels["Group"]` | an older study with a factorial design keeps it: group label = `experiment.groupLabel(animal)` |
| **Animal** (动物) | `Animal` (code, sex, group) | created on the fly from the animal ID typed / parsed at import |
| **Session** (实验) — one video of one animal at one timepoint / trial | `Recording` (video, pose, QC, decision) + its `Session` for the task's assay | the Session is created **at import** (not after QC), so it appears in the task at once |

Hierarchy everywhere: **Task → Group → Animal → Session (timepoint · trial · date)**.

Legacy data (iPhone 1.0–1.3, Mac ≤ 1.3.5) must open unchanged:
- A study with several assays (planned or present in its sessions) appears as **one task per assay**
  ("Study name · Gait", "Study name · Cylinder"), sharing the study's groups and animals.
  A task reference is therefore `(experimentID, assay)`.
- Videos in no study → a list "Not in a task" with an action "Move to Task…" (choose a task; the
  video's session for that task is created).
- Sessions of videos in no study (1.3 "analyse any task") → shown in "Not in a task" too.

## 2. Flow

1. **New Task** (primary action when there is no task; always in the toolbar / top bar).
   Step 1 — choose the paradigm (list grouped by purpose; one line of explanation each, no icons):
   - Motor: Gait analysis · Cylinder test
   - Pain and itch: Itch (scratching) · Spontaneous pain
   - Affective and repetitive: Tail suspension · Self-grooming
   - Seizure: Seizure scoring
   Step 2 — name (prefilled "<Paradigm> <date>"), groups (default two empty rows "Control",
   "Treatment" as placeholders; may be left empty), optional timepoints, optional note.
   Create → the task opens.
2. **Add Videos** (only inside a task; the task's paradigm is fixed). Choose / drop files or folders.
   A table assigns per video: animal ID (parsed from the file name), group (menu of the task's groups;
   pre-filled when the file or folder name contains a group name; animals already in the task keep
   their group), timepoint, trial. Pose model (two choices, see §5). Add → each video becomes a
   session of the task, queued for tracking. Duplicate files are detected.
3. **Processing** runs automatically in the background (pose model once per video); progress is shown
   on the session rows and on one "Processing" page. Pausing, quitting or a crash loses nothing.
4. **QC**: a video that passes is included automatically. Otherwise it waits in "Needs review"
   (the task shows a count); include / exclude with a reason. Excluded sessions stay visible in the
   task, marked, and are left out of group results.
5. **Calibration** only for paradigms that need it (cylinder rim, gait scale); offer "use for all
   sessions of this task".
6. **Results**:
   - Session page: Summary · Review (video + events) · Measures; parameters in a side panel / sheet.
   - **Task page** = the hub: header (name, paradigm, counts by state), primary action Add Videos,
     sections **Sessions** (grouped by group → animal), **Results** (group comparison: each animal one
     dot, group mean ± SEM; time course per group for binned measures), **Design** (groups, animals,
     timepoints, QC criteria, parameters/presets, blinding), **Export** (task scope).
7. **Export** of a task: summary (one row per session), behaviour segments, time bins, QC table,
   methods, README, manifest — the existing exporter, scoped to `(experimentID, assay)`.

## 3. Navigation

**Mac** (one window): sidebar
- Tasks — each task (name; secondary text = paradigm), expandable into its groups.
- Lists — Processing (queue), Needs review, Failed, All videos, Not in a task (only when not empty).
Main area: the selected task page (or group = same page filtered), or the list page. Session page
pushed on double-click. Toolbar: New Task… (⇧⌘N), Add Videos… (⌘O, enabled when a task is selected),
Export… (⌘E). No separate Overview dashboard; with no task, the main area shows a short welcome with
one button "New Task…".

**iPhone / iPad**: tabs **Tasks · Processing · Settings** (Data/Library folded into Tasks and "All
videos" list reachable from Tasks). Tasks tab: list of tasks (name, paradigm, "12 sessions · 3 need
review"), "+" → New Task. Task screen: segmented control Sessions | Results | Design, primary button
Add Videos. Session screen: existing detail (Summary / Review / Measures).

## 4. Visual rules (both apps)

- **No decorative icons or emoji.** Remove SF Symbols from: buttons, menus, list rows, sidebar rows,
  section / card headers, banners, empty states, status tags, assay badges, onboarding. Remove emoji /
  pictographic characters (★ ✓ ✗ ⚠ ➜ etc.) from UI strings and docs. Status = short coloured text or
  a small coloured dot; assay = text (name or short code such as GAIT), optionally on a tinted chip.
- Keep only functional glyphs where text cannot fit: playback controls (play / pause / step), the iOS
  tab bar symbols, the system's own chevrons / close buttons, a "+" toolbar button on iOS (with an
  accessibility label).
- Typography first: clear hierarchy (large title, section titles, secondary text), generous spacing,
  one accent colour, consistent card style, numbers in monospaced digits.
- One primary action per screen; destructive actions confirmed; advanced settings behind
  "Advanced" / disclosure.
- Charts (Swift Charts): colour-blind-safe group palette (Okabe–Ito: #0072B2, #E69F00, #009E73,
  #CC79A7, #56B4E9, #D55E00, #F0E442, #000000), each animal a dot (jittered), group mean as a thick
  short bar with ± SEM whiskers, axis titles with units, no chart junk (no gridline clutter,
  no 3D, no gradients), consistent sizes, readable in light and dark mode. Time course: mean ± SEM
  per group per bin (line + band). Show n per group.

## 5. Pose models (both apps — `Shared/Pose/PoseModels.swift`, identical file)

- Offered: **CylinderPose7_FP16_640** (default; visible light; 7 keypoints) and
  **PalmReaderPose8_640_W8A16** (near-infrared dark box; 8 keypoints mapped onto the stored 7, no mouth).
- **CylinderMousePoseV2 (38 MB) is removed** from both apps. It stays a known label: a video without
  a recorded model was tracked with it; tracking such a video again uses FP16 (`runnable`).
- Decoder generalised to K keypoints (26/27 channels for 7, 29/30 for 8); Float16 outputs supported.

## 6. Never lose data (both apps)

- Writes coalesced (~0.4 s) and on a serial queue; flush immediately for decisions, deletes, imports,
  task edits; flush when the app goes to the background / Mac sleeps / quits.
- **Recently Deleted**: deleting sessions / videos / tasks moves their folders into
  `<library>/Recently Deleted/<entry>/` (same layout) for 30 days; Restore; Undo right after a delete.
- **Daily metadata backups** (`<library>/Backups/metadata-<UTC date>-<reason>.json`, keep 14 daily +
  10 before-change) and before deletes / bulk changes; restore never deletes anything.
- Every lookup by id is O(1) (index verified on every hit). No O(n²) work in list rows.
- Text fields commit on submit, on focus loss and on disappear.
- Long work (tracking, analysis, export, file copies, JSON decoding) never on the main thread.

## 7. Shared files

These files are byte-identical in both apps (`tools/verify_shared.sh`): `Analysis/*`, `App/L10n.swift`,
`Pose/PoseTypes.swift`, `Pose/PoseModels.swift`, `Data/{Session,Recording,Experiment,PoseStorage,
Exporter,StudyExport}.swift`. Change them only together, in both copies.
