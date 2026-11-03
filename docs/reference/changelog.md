# Release notes

## RodentLimb for Mac

### 1.3.5

- **Two pose models.** *Visible light* — [CylinderPose7](../models/cylinderpose7.md) (FP16, 19 MB) — is the default for new imports; *Near-infrared, dark box* — [PalmReaderPose8](../models/palmreader8.md) — is the second choice. The full-precision CylinderMousePoseV2 package is no longer bundled, which makes the app much smaller.
- Videos tracked earlier keep their keypoints. Videos without a recorded model (iPhone libraries, Mac versions before 1.3.2) are still labeled CylinderMousePoseV2 in exports; the `pose_model` column, the methods text and the manifest name the model each video actually used.
- **Video decoding check at import.** RodentLimb asks macOS whether it can decode each file and decodes one frame. Formats without a decoder (for example AV1 on M1 and M2 Macs) are marked *Unreadable*, with instructions to convert to H.264 MP4. Such videos now fail at once with the reason instead of being retried.

### 1.3.3

- CylinderPose7 FP16: the visible-light network stored in half precision — every weight within 0.044 % of the full-precision model — at half the size.
- The re-track menu, queue cards and inspector name the models distinctly. The `pose_model` column of `qc_videos.csv` gives the model's full name.

### 1.3.2

- **Near-infrared model** PalmReaderPose8 for videos filmed from below in the dark under near-infrared light (dark-box / Blackbox-style rigs).
- Choose the model at import; re-track a video with another model from its page or the table's context menu; set the default in **Settings › Processing**.
- The model's keypoints are mapped onto the stored seven (snout → nose; this model has no mouth, so the analyses use the nose), so analyses, QC, review and export work unchanged. The model used is shown on the video page, inspector, queue, analysis and overview, and written into every export.

### 1.3.1

- Fixed a freeze and crash when opening *Needs Review*, *All Videos* or a study page.
- When tracking finishes, the queue page lists what to do next: videos waiting for a QC decision, included videos without a task, analyses ready to open.
- **Simplified Chinese** interface, switchable in the app (menu **RodentLimb › Language · 语言**, the globe in the sidebar, the welcome page or Settings).
- **Data safety**: Recently Deleted (30 days, with Undo), automatic backups before deletions and bulk changes, immediate saving of inclusion decisions, and a warning when two Macs open the same library.
- Faster large libraries (indexed lookups).
- **Protocol presets** in each analysis's parameters, matched to published protocols. See [Parameters](../guide/parameters.md).

### 1.3

First Mac version. The analysis code is the same as the iPhone app's.

- **Batch processing**: drag in files or folders; animal, timepoint and trial suggested from file names; 1–3 videos tracked at once with live preview, progress and time remaining; pause, resume, reorder and cancel; frame-by-frame checkpoints; automatic retries; offline drives wait in the queue; low-disk pause; activity log.
- **Library**: the same folder structure as the iPhone app; videos referenced in place; native sortable tables with an inspector; keyboard review.
- **Export** of a selection, a task, a study or the whole library, with a data dictionary and manifest; an event / bout table across all videos; BORIS, DeepEthogram / daart and DeepLabCut formats.
- Seven tasks: tail suspension, cylinder, gait, itch, spontaneous pain, self-grooming and seizure scoring.
- Not on the Mac: recording video, and rendering a skeleton video.

## RodentLimb for iPhone

### 1.1.2

- **Smooth review**: picture and keypoints stay in sync while you scrub. Swipe sideways on the video to step frame by frame.
- The interface no longer redraws whole screens while a video is processing. Saving and pose-CSV export happen in the background.
- Typing: Return moves to the next field, the number pad has a Done key, and dragging dismisses the keyboard.

### 1.1

- New app icon; paw colors match it.
- Simpler screens. Results have three tabs: Summary, Review and Measures. Short welcome tour on first launch. Liquid Glass on iOS 26.
- **Gait methods v2**: straight-walking and run-end filters, speed-matched values at a reference speed, stride variability (CV), step length, gait pattern (walk/trot/gallop/bound), nose and tail-base lateral sway.
- Results from 1.0 are recomputed automatically when first opened.

### 1.0

- First version: tail suspension, cylinder and gait analysis with CylinderMousePoseV2; English and Chinese interface; CSV and methods export.
