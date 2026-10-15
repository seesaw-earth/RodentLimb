# FAQ & troubleshooting

## Pose detection

### "The mouse was detected in only …% of frames"

The model found no mouse above the detection confidence in many frames. Check that the whole animal is in view, the light is even and the image is sharp. You can also lower **Detection confidence** in Settings and choose **⋯ › Re-run tracking**.

### Paws jump or swap sides

Single-frame jumps are removed by the median filter. If paws swap for longer, the view may be unusual for the model (V2 was trained on cylinder videos). Raising **Keypoint confidence** drops uncertain points. The lasting fix is to add labeled frames from your setup to the training set.

### Left and right are reversed

If the camera image is mirrored (common with bottom views through a mirror), turn on **Swap left/right labels** in Parameters (cylinder and gait).

### Processing paused

iOS does not allow GPU work in the background. When you switch apps, the current video pauses and restarts automatically when RodentLimb is active again. Keep the app open for long batches; the screen stays awake while processing.

## Tail suspension

### Breathing is scored as mobile, or swinging as immobile

Adjust the **motion threshold**. Play the Review tab and watch the *Immobile / Mobile* chip. Set one value for the whole study.

### The clasping score looks wrong

It needs both hind paws visible from the front or back. From the side it cannot work. Treat it as an estimate and confirm on the video.

## Cylinder

### No contacts are found

Calibrate first: the rim circle (bottom view) or the floor line (side view). Check that the **Camera** parameter matches your view.

### Contacts are missed or extra ones appear

Adjust **Still paw speed** (higher finds more), **Wall zone** or **Paw height**, and **Minimum contact**. Then review the list and relabel what remains. Edits are kept.

## Gait

### "Only N strides passed the filters"

Use longer or more runs, or relax **Minimum walking speed** and **Maximum turning rate**. If the mouse never walks steadily, gait measures are unreliable anyway.

### Speed-matched values are blank

The animal never walked near the reference speed. Lower or raise the **reference speed** for the whole study, or use the raw values with per-stride speed as a covariate.

### Duty factor looks too high

Check the frame rate: below 50 fps, stance is quantized coarsely and biased upward. Record at 60 fps or more.

## Data

### Where are my files?

Files › On My iPhone › RodentLimb. See [Files & exports](./files.md).

### Exports are in English but my interface is Chinese

That is intentional: exported keys and text are always English, for scripts and papers. Subject IDs, groups and notes are kept exactly as typed.
