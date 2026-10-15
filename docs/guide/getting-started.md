# Quick start

This walks through one complete analysis. It takes a few minutes plus the processing time of the video.

## 1. Start a new analysis

On **Home**, tap **New analysis**, or tap one of the three assay tiles to preselect it.

1. Choose the **assay**: tail suspension, cylinder test or gait analysis.
2. Tap **Add videos** and pick from **Photos** or **Files**. You can add many videos at once, one mouse per video.
3. Check the **subject IDs**. They default to the file names; tap one to edit, and press Return to move to the next.
4. Optionally enter a **group** (for example *Vehicle* or *6-OHDA*) and notes.
5. Tap **Analyze**.

::: tip Batches
Add a whole cohort at once. Videos are processed one after another in the background queue while you keep working.
:::

## 2. Wait for pose detection

The model reads every frame. Progress is shown on Home and on the session page. Keep the app open: if you switch to another app, processing pauses and resumes by itself when you return.

## 3. Calibrate (cylinder, optional for gait)

- **Cylinder test**: drag the circle onto the cylinder rim (bottom view) or the line onto the floor (side view). **Auto-fit** proposes a starting position from the tracking.
- **Gait**: optionally drag a ruler across a known distance and enter it in cm. Without it, lengths are reported in body lengths.
- **Tail suspension** needs no calibration.

If the camera did not move, choose **Save and use for all videos of this assay**. See [Calibration](./calibration.md).

## 4. Read the result

Each result has three tabs:

- **Summary**: the key numbers, any notes, and one main chart.
- **Review**: the video with keypoints drawn on it, plus the events behind the numbers.
- **Measures**: every measure, grouped, with the detailed charts.

See [Results & review](./results.md).

## 5. Adjust and export

- **Parameters** (bottom bar): thresholds and windows. Results update as you move a slider. **Apply to all sessions of this assay** keeps a study consistent.
- **Export**: summary, events or strides, frame-by-frame pose CSV and a methods text. See [Data, groups & export](./data.md).
