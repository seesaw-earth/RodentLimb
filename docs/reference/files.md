# Library & files

## The library

Everything RodentLimb knows is stored in one folder, the **library**. By default it is `Documents/RodentLimb` inside the app's container; **File › Show Library in Finder** opens it. With **File › Open Library…** you can keep a library anywhere, for example in a project folder on an external drive.

```
RodentLimb/
├── Experiments/<id>.json        studies: design, animals, groups, blinding, QC criteria
├── Recordings/<id>/             one folder per video
│   ├── recording.json           animal, timepoint, QC report, included / excluded and why
│   ├── pose.bin                 keypoints of every frame (a few MB per hour of video)
│   ├── source.json              where the video is (bookmark, path, fingerprint) and which pose model tracked it
│   ├── checkpoint/              tracking in progress; removed when the video is done
│   └── thumbnail.jpg            list thumbnail
├── Sessions/<id>/               one folder per analysis (one video × one task):
│                                session.json (parameters, calibration, manual edits) and result.json
├── Logs/activity-<date>.log     batch log: imports, each video, failures, recovery
├── Recently Deleted/<id>/       deleted items, kept for 30 days
├── Backups/metadata-<date>-<reason>.json   backups of studies, video information and parameters
└── .rodentlimb-lock.json        which Mac is using this library
```

The structure is the same as the iPhone app's library, so a library copied from **Files › On My iPhone › RodentLimb** opens on the Mac.

**Videos are not copied by default.** RodentLimb refers to them where they are (a sandbox security-scoped bookmark), so they take no extra disk space. If you prefer a self-contained library, choose to copy them under *Video files* at import, or turn on *Copy videos into the library by default* in Settings. If a drive with referenced videos is unplugged, those videos show as offline and wait in the queue until it is connected again.

## Safety nets

- **Recently Deleted** (**File › Recently Deleted…**, ⌥⌘⌫). Deleting a video, an analysis or a study moves its folder into `Recently Deleted/` for 30 days; restore it with one click. A video comes back with its analyses. The original video files you imported by reference are never deleted.
- **Backups.** Every day the library is opened, and before deletions and bulk changes (bulk include / exclude, *Apply to…* for parameters), RodentLimb writes the studies, video information, inclusion decisions, analysis parameters and manual labels to `Backups/` (one compact JSON file; the last 14 daily and 10 pre-change backups are kept). Restore one in **Settings › Advanced › Data safety**. Restoring does not change tracking results or delete anything, and backs up the current state first.
- **Library lock.** `.rodentlimb-lock.json` is refreshed every minute while a Mac has the library open. If a second Mac opens the same library (shared drive, iCloud Drive), it is warned, so the two do not overwrite each other. The lock records that Mac's name and the macOS user name, and is never uploaded anywhere.
- **Checkpoints.** Tracking writes every frame's keypoints to `checkpoint/` and flushes at least every 2 s. After a pause, quit, sleep, crash or power cut, tracking continues after the last complete frame, with the same result as an uninterrupted run.

## `pose.bin`

The keypoints of one video, written once by tracking. Little-endian:

```
"RLPS" · UInt32 version (1) · UInt32 header length · header JSON ·
times (Float64 × n) · box confidence (Float32 × n) ·
for each keypoint: x, y, confidence (Float32 × n each)
```

The header holds the frame size, fps, duration and the pose model's name and version. Keypoint order: `L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth`. Coordinates are pixels in the displayed (rotation-corrected) frame, origin at the top left; missing keypoints have x = y = −1 and confidence 0. Libraries from before version 1.2.1 stored `pose.plist`; it is read and converted to `pose.bin` once.

You do not need to read `pose.bin` yourself: the export writes the same data as CSV (`pose/`) and in DeepLabCut format (`pose_dlc/`).

## Export files

The export folder and its tables are described in [Export](../guide/export.md). Exports are always in English. Summary tables share the same first 10 columns and can be joined on `analysis_id`; measure columns are named *key [unit]*.

### Frame-by-frame pose (`pose/`)

`frame, time_s, box_confidence`, then `<keypoint>_x, <keypoint>_y, <keypoint>_confidence` for the seven keypoints, in pixels of the displayed frame. Missing points have empty x and y.

### DeepLabCut format (`pose_dlc/`)

Three header rows (scorer, body parts, coords): 7 body parts × `x, y, likelihood`. Read with `pandas.read_csv(f, header=[0, 1, 2], index_col=0)`. Opens in DeepLabCut, SimBA and Keypoint-MoSeq.

## Measure keys

The keys are stable across versions, so scripts can rely on them. Examples:

| Task | Keys |
|---|---|
| Tail suspension | `immobility_s`, `immobility_pct`, `latency_s` |
| Cylinder | `contra_use_pct`, `asymmetry_pct` |
| Gait | `stride_len_hind`, `duty_hind`, `bos_hind`, `ref_stride_len_bl`, `phase_LH_RH`, `pattern_trot_pct` |
| Itch | `scratch_bouts_n`, `scratch_time_s`, `latency_s`, `bouts_per_min`, `trains_n`, `side_index_pct` |
| Spontaneous pain | `lick_phase1_s`, `lick_phase2_s`, `flinch_n`, `lick_latency_s`, `lick_ipsi_share_pct` |
| Self-grooming | `groom_time_s`, `groom_bouts_n`, `face_s`, `interrupted_pct`, `incorrect_transitions_pct` |
| Seizure | `max_stage`, `latency_jerk_s`, `latency_generalized_s`, `latency_tonic_s`, `jerks_n`, `episodes_n` |
| All tasks | `edited_n`, `pose_coverage_pct` |

The `README.txt` of every export lists every column of every file.
