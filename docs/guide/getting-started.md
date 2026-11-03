# Quick start on Mac

This walk-through takes a folder of videos from a new task to an exported table. Since version 1.4 everything starts from a **task**: you choose the test first, then add its videos. Each step links to its page for details.

## 1. Install and open

Install RodentLimb from the [App Store](https://apps.apple.com/app/id6822935387) and open it. Choose English or 简体中文 under **RodentLimb › Language · 语言** (also at the bottom of the sidebar and in Settings).

The app keeps its work in a **library** folder. The default library is created for you; to keep a project on an external drive, use **File › Open Library…** and choose a folder. See [Library & files](../reference/files.md).

## 2. Create a task

Click **New Task** in the toolbar (⇧⌘N). Choose the paradigm (tail suspension, cylinder, gait, itch, spontaneous pain, self-grooming or seizure scoring), then give the task a name, its groups (for example *WT* and *KO*), timepoints, notes and whether it is blinded. The sidebar lists every task with its groups; select a group to see only its sessions. See [Studies, groups & blinding](./data.md).

## 3. Add videos

On the task page click **Add Videos…** (⌘O), or drop videos or whole folders on the window. The table reads each video's length, frame rate and resolution and warns about files the Mac cannot decode.

- Check the **animal**, **group**, **timepoint** and **trial** read from the file and folder names, or set a naming rule. Animals already in the task keep their group.
- Choose the **pose model**: *Visible light* (default) for room-light videos, *Near-infrared, dark box* for videos filmed from below in the dark.

Each video becomes a session of the task at once. See [Importing videos](./import.md).

## 4. Let the queue run

Tracking starts automatically. The **Processing** page shows the video being tracked with its keypoints, the progress, frames per second and the time left for the whole queue. You can pause (⌘.), reorder or cancel videos, close the window, or quit and continue later. See [Processing queue](./processing.md).

## 5. Check tracking quality

When a video is tracked, it is checked against the task's criteria (by default: mouse tracked in ≥ 90 % of frames, no gap longer than 10 s, frame rate ≥ 25 fps). Videos that pass are included automatically. The others appear under **Needs Review**: watch the tracking, then press **I** to include or **E** to exclude with a reason. See [Quality control & inclusion](./qc.md).

## 6. Score and calibrate

The task page has three tabs: **Sessions** (every video with its state, for example *Tracking 45 %*, *Needs review* or *Needs calibration*), **Results** (group comparison, completeness, exclusions) and **Design**. Open a session to see its result. For the cylinder test, mark the cylinder rim (bottom view) or floor line (side view); for gait, optionally a cm ruler. See [Calibration](./calibration.md) and [Tasks, parameters & presets](./parameters.md).

## 7. Review events

The **Review** tab of a session plays the video with the keypoints drawn on it and lists every detected event: each wall contact, scratching bout, licking episode or seizure. Step through them with ↑/↓, relabel with the number keys, and the measures update. See [Results & review](./results.md).

## 8. Export

Press ⌘E. On a task page the task is exported (or the sessions you selected). RodentLimb writes a folder with a summary table, the behavior segments, time bins, the QC table, a methods paragraph and a data dictionary. See [Export](./export.md).

::: tip Before a real study
Track a few pilot videos, check the overlay, score a few by hand and adjust the parameters until the automated values agree. Then fix the settings and apply them to every session of the task. See [Validation & limits](../principles/validation.md).
:::
