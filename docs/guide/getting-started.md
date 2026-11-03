# Quick start on Mac

This walk-through takes a folder of videos from import to an exported table. Each step links to its page for details.

## 1. Install and open

Install RodentLimb from the [Mac App Store](https://apps.apple.com/app/id6822935387) and open it. A welcome page explains the main steps. Choose English or 简体中文 under **RodentLimb › Language · 语言** (also in the sidebar and in Settings).

The app keeps its work in a **library** folder. The default library is created for you; to keep a project on an external drive, use **File › Open Library…** and choose a folder. See [Library & files](../reference/files.md).

## 2. Optional: create a study

A study holds the design: factors such as genotype or treatment, timepoints, animals, blinding and the quality-control criteria. Create one with **File › New Study…** (⇧⌘N) before importing, so the videos go straight into it. You can also import first and assign videos later. See [Studies, groups & blinding](./data.md).

## 3. Import videos

Drag videos or whole folders into the window, or press ⌘O. The import table reads each video's length, frame rate and resolution and warns about files the Mac cannot decode.

- Check the **animal**, **timepoint** and **trial** read from the file names, or set a naming rule.
- Choose the **pose model**: *Visible light* (default) for room-light videos, *Near-infrared, dark box* for videos filmed from below in the dark.
- Tick the **planned tasks** (for example *Itch (scratching)*), so that analyses are created as soon as videos are included.

See [Importing videos](./import.md).

## 4. Let the queue run

Tracking starts automatically. The **Processing** page shows the video being tracked with its keypoints, the progress, frames per second and the time left for the whole queue. You can pause (⌘.), reorder or cancel videos, close the window, or quit and continue later. See [Processing queue](./processing.md).

## 5. Check tracking quality

When a video is tracked, it is checked against the study's criteria (by default: mouse tracked in ≥ 90 % of frames, no gap longer than 10 s, frame rate ≥ 25 fps). Videos that pass are included automatically. The others appear under **Needs Review**: watch the tracking, then press **I** to include or **E** to exclude with a reason. See [Quality control & inclusion](./qc.md).

## 6. Score and calibrate

Included videos get an analysis for each planned task. Open one to see its result. For the cylinder test, mark the cylinder rim (bottom view) or floor line (side view); for gait, optionally a cm ruler. Settings for one camera position can be used for every analysis of that task in the study. See [Calibration](./calibration.md) and [Tasks, parameters & presets](./parameters.md).

## 7. Review events

The **Review** tab plays the video with the keypoints drawn on it and lists every detected event: each wall contact, scratching bout, licking episode or seizure. Step through them with ↑/↓, relabel with the number keys, and the measures update. See [Results & review](./results.md).

## 8. Export

Press ⌘E and choose the scope: the selection, a task, a study or the whole library. RodentLimb writes a folder with a summary table per task, the behavior segments, time bins, the QC table, a methods paragraph and a data dictionary. See [Export](./export.md).

::: tip Before a real study
Track a few pilot videos, check the overlay, score a few by hand and adjust the parameters until the automated values agree. Then fix the settings and apply them to every analysis of the study. See [Validation & limits](../principles/validation.md).
:::
