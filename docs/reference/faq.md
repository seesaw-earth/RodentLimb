# FAQ & troubleshooting

## Getting started

### Which Macs are supported?

macOS 14 Sonoma or later, on Apple silicon or Intel. Tracking uses the Neural Engine and GPU where available; Apple silicon is much faster.

### Is it the same app as RodentLimb for iPhone?

Yes. RodentLimb is one App Store app for iPhone and Mac. The Mac version is made for batches of long videos; it uses the same analysis code, so the same keypoints give the same measures on both. A library copied from the iPhone opens on the Mac. See [RodentLimb on iPhone](../guide/iphone.md).

### Does RodentLimb upload my videos?

No. Everything runs on your Mac; the app has no network access. See [Privacy](../privacy.md).

## Importing and tracking

### A video is marked “Unreadable”

macOS has no decoder for its format (for example AVI or MKV, or AV1 on M1 and M2 Macs). Convert it to H.264 MP4; the command is in [Recording videos](../guide/recording.md#file-formats).

### Which model should I choose?

*Visible light* (CylinderPose7) for normal room light; *Near-infrared, dark box* (PalmReaderPose8) for videos filmed from below in the dark under near-infrared light. Use one model for every video of a study. See [Pose models](../models/).

### My videos were tracked with CylinderMousePoseV2

Videos tracked on the iPhone or with an earlier Mac version carry that label. Their keypoints are still valid and are analyzed the same way. If you want one model for the whole study, re-track them with CylinderPose7 (**Re-run Tracking** on the video's page).

### “The mouse was detected in only …% of frames”

The model found no mouse above the detection threshold in many frames. Check that the whole animal is in view, the light is even and the image is sharp. You can lower **Detection threshold** in **Settings › Processing** and re-run tracking.

### Tracking stopped: Mac asleep, app quit, power cut

Start the queue again. Tracking continues from the last saved frame, with the same result as an uninterrupted run. To avoid interruptions, turn on *Keep the Mac awake while tracking* in Settings.

### A drive with my videos was unplugged

Videos on that drive show as offline and wait in the queue. Connect the drive and tracking continues. If you moved the files, use **Locate Video…** on the video's page; RodentLimb checks that it is the same file.

## Pose quality

### Paws jump or swap sides

Single-frame jumps are removed by the median filter. For longer errors, try *Keypoints: confidence 0.6 + remove jumps* (a protocol preset) and check the gap counts in QC. If the view is unusual for the model, the lasting fix is labeled frames from your setup.

### Left and right are reversed

If the camera image is mirrored (common with bottom views through a mirror), turn on **Swap left/right labels** in the parameters (cylinder and gait).

## Tasks

### Tail suspension: breathing is scored as mobile, or swinging as immobile

Adjust the **motion threshold** while watching the *Immobile / Mobile* indicator in the review player. Set one value for the whole study.

### Cylinder: no contacts are found

Calibrate first: the rim circle (bottom view) or the floor line (side view). Check that the **Camera** parameter matches your view.

### Gait: “Only N strides passed the filters”

Use longer or more runs, or relax **Minimum walking speed** and **Maximum turning rate**. If the mouse never walks steadily, gait measures are unreliable anyway. Below 50 fps, duty factor is biased upward; record at 60 fps or more.

### Itch, pain, grooming or seizure: latencies look wrong

Set the **injection time**: by default the injection is at the start of the video. Latencies, phases and time bins are measured from it.

### Pain: no licking found with the near-infrared model

That model has no mouth keypoint, so licking is measured from the snout. Check that the injected paw is visible from below, and that **Injected paw** is set correctly.

### Seizure: events before the injection

They are listed but not counted. Their number is a built-in check of false positives in your setup; if it is high, raise the thresholds for the whole study.

## Data

### Where are my files?

In the library: **File › Show Library in Finder**. See [Library & files](./files.md).

### I deleted something by mistake

Open **File › Recently Deleted…** (⌥⌘⌫) and restore it. Deleted items are kept for 30 days. Analysis parameters and labels can also be restored from a backup in **Settings › Advanced › Data safety**.

### Exports are in English but my interface is Chinese

That is intentional: exported keys and text are always English, for scripts and papers. Animal IDs, groups and notes are kept exactly as typed.
