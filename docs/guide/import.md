# Importing videos

## Add files

Drag videos or folders into the window, or choose **File › Import Videos…** (⌘O). Folders are searched recursively. To import straight into a study, use **Import Videos into This Study…** (⇧⌘I) on the study page.

Before anything is imported, the import table reads each video's **length, frame rate and resolution** and test-decodes one frame:

- Files macOS cannot open, or encoded with a codec this Mac cannot decode (for example AV1 on M1/M2 Macs), are marked **Unreadable**, with instructions for converting them to H.264 MP4. See [Recording videos](./recording.md#file-formats).
- A file that has already been imported is recognized and flagged as a duplicate.

## Animal, timepoint and trial from the file name

RodentLimb fills in the **animal**, **timepoint** and **trial** from file and folder names. If your names follow a pattern, set a rule, for example *split at `_`; part 1 is the animal, part 2 the timepoint*. Select several rows to edit them together.

## Options for this import

| Option | What it does |
|---|---|
| **Study** | Puts the videos into an existing or new study, or none |
| **Timepoint, group, notes** | Applied to every video in the import (groups stay hidden in a blinded study) |
| **Planned tasks** | Analyses created for each video once it is included. Without a task, videos are tracked and checked but not scored until you assign a task |
| **Pose model** | *Visible light — default (CylinderPose7 FP16)* or *Near-infrared, dark box (PalmReaderPose8)*. See [Models & provenance](../models/) |
| **Video files** | *Keep videos where they are* (recommended) or *Copy videos into the library*. Copying shows the space needed and the space free |

The default model for new imports can be changed under **Settings › Processing › Pose model**.

## Videos stay where they are

By default videos are **referenced, not copied**: RodentLimb keeps permission to read them (a security-scoped bookmark) and never modifies them. To recognise a moved or replaced file, it stores a fingerprint made of the file size, the modification date and the first and last megabyte.

- If a video is moved, use **Locate Video…** to point to its new place.
- If a drive is not connected, its videos wait in the queue as **offline** and continue when it is back.
- If a file was replaced by a different one, RodentLimb says so and tracks it again.

## Re-tracking with the other model

To track a video again, for example with the other model, right-click it in a video table and choose **Re-run Tracking…** with the model you want, or use **Re-run Tracking** on the video's page. Its keypoints are replaced and its analyses are recomputed.
