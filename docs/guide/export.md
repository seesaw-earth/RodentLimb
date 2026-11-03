# Export

Press ⌘E (**File › Export…**), choose the **scope** — the selection, one task, one study or the whole library — and the kinds of files, then a folder. RodentLimb writes one folder:

```
RodentLimb_<scope>_<date_time>/
├── README.txt                  data dictionary: every file and every column
├── export_manifest.json        app and model versions, options, each analysis's parameters,
│                               calibration and number of manual edits
├── qc_videos.csv               tracking quality, QC verdict, included / excluded and why, pose model
├── study_<name>_design.txt     design and methods text of the study
├── ITCH_Itch_scratching/       one folder per task
│   ├── ITCH_summary.csv        one row per analysis: design columns, QC, then every measure
│   ├── ITCH_segments.csv       every event or bout of every video (start, end, duration, time after
│   │                           injection, automatic label, reviewed label, edited, counted)
│   ├── ITCH_ethogram.csv       behavior intervals per track
│   ├── ITCH_time_bins.csv      time course in bins from the injection (long format)
│   ├── ITCH_methods.txt        methods paragraph with the parameters and references
│   ├── ITCH_boris_events.tsv   (optional) BORIS aggregated events
│   ├── frame_labels/           (optional) frame-by-frame 0/1 labels (DeepEthogram / daart)
│   └── per_video/              (optional) one folder per video, as the iPhone exports one analysis
├── pose/                       (optional) frame-by-frame keypoints, RodentLimb layout
└── pose_dlc/                   (optional) keypoints in DeepLabCut format
```

## The tables

- All summary tables start with the same 10 columns — `analysis_id`, `study`, `animal_id`, `blind_code`, `sex`, `group`, `timepoint`, `trial`, `video`, `included` — so tables can be joined on `analysis_id`. Measure columns are named *key [unit]*.
- The tables are in **long format**, ready for R, Python, SPSS or Prism (two-way or mixed ANOVA, or linear mixed models with the animal as a random effect).
- **Segments**: tail suspension writes immobility and climbing bouts (plus a per-minute table); the cylinder test writes every wall contact; gait writes a stride table and a footprint table instead.
- Files are UTF-8 with a byte-order mark, so Excel shows Chinese IDs correctly. BORIS and frame-label files have no byte-order mark.
- Exports are always in English, whatever the interface language.

## Interoperability

| File | Opens in |
|---|---|
| `*_boris_events.tsv` | BORIS, as aggregated events |
| `frame_labels/` | DeepEthogram, daart |
| `pose_dlc/` | DeepLabCut, SimBA, Keypoint-MoSeq (read with `pandas.read_csv(f, header=[0, 1, 2], index_col=0)`: 7 body parts × x, y, likelihood) |

## Blinded studies

While a study is blinded, the export leaves out the animal ID, the group and the original file name; the blind code identifies each animal.

## The methods paragraph

`*_methods.txt` describes, for each analysis, the pose model, the keypoint cleaning, the task's scoring rules with your parameter values, the number of manual edits and the references. Its first sentence names the model that tracked the video. Copy it into your methods section and adapt it; see also [How to cite](../models/cite.md).
