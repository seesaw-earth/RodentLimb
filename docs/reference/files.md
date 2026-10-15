# Files & exports

## Where data are stored

**Files › On My iPhone › RodentLimb › RodentLimb › Sessions**. One folder per session:

| File | Content |
|---|---|
| `session.json` | Subject, group, notes, assay, parameters, calibration, label edits |
| `video.mov` / `.mp4` | Copy of the imported video |
| `pose.plist` | Keypoints of every frame (binary property list) |
| `result.json` | Latest analysis |
| `skeleton.mp4` | Only if *Also render skeleton video* was on |

## Session export

All files start with `<subject>_<ASSAY>` (ASSAY = TST, CYL or GAIT). All text is English.

### `…_summary.csv`

Long format with columns `field, value, unit`: session metadata (subject, group, assay, video, created, fps, duration_s, model, model_version, notes), then every measure by key, then the notes (`note_info`, `note_warning`, `note_error`).

### Tail suspension

- `…_immobility_bouts.csv`: `bout, start_s, end_s, duration_s, overlaps_window`
- `…_per_minute.csv`: `minute, immobility_s`

### Cylinder

- `…_contacts.csv`: `event, onset_s, offset_s, rear, auto_label, final_label, edited, counted`. Labels are `left`, `right`, `both` or `ignore`.

### Gait

- `…_strides.csv`: `paw, start_s, end_s, stride_s, stance_s, swing_s, duty, stride_length_<unit>, speed_<unit>_per_s` (unit = `cm` or `BL`). Use the per-stride speed for speed-adjusted statistics.
- `…_footprints.csv`: `paw, strike_s, x_px, y_px`

### `…_methods.txt`

A methods paragraph with your parameter values and the references for the assay.

### `…_pose.csv` (optional)

`frame, time_s, box_confidence`, then `<keypoint>_x, <keypoint>_y, <keypoint>_confidence` for `L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth`. Coordinates are pixels in the displayed (rotation-corrected) frame, with the origin at the top left. Missing points have empty x/y.

## Group export

From the Data tab (**Select › Export CSV**): one file per assay, `RodentLimb_<ASSAY>_<n>_sessions_<date>.csv`. One row per session: `subject, group, video, created, status`, then one column per measure as `key [unit]`.

## Measure keys

The keys are stable across versions, so scripts can rely on them. Examples: `immobility_s`, `immobility_pct`, `latency_s`, `contra_use_pct`, `asymmetry_pct`, `stride_len_hind`, `duty_hind`, `bos_hind`, `ref_stride_len_bl`, `phase_LH_RH`, `pattern_trot_pct`, `nose_lateral_amp_bl`. Each assay page lists its measures.
