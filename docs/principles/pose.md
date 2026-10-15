# Pose model & cleaning

## The model

RodentLimb uses **CylinderMousePoseV2**, a YOLO pose model with 7 keypoints (LF, LH, RF, RH paws, tail base, nose, mouth). It was distilled from a DeepLabCut model trained on cylinder-test videos, and runs on the iPhone through Core ML. V2 was chosen over V1 after a side-by-side comparison on the same videos.

For every frame of the video:

1. The frame is letterboxed to the model's square input (640 × 640).
2. The model returns candidate detections. The most confident one above the **detection confidence** (Settings, default 0.25) is kept, since there is one mouse per video.
3. The seven keypoints of that detection are mapped back to the original frame. The video's rotation is applied, so positions match what you see in the player.

The keypoints are saved once per video (`pose.plist`). Nothing after this step needs the model again.

## Cleaning

Before any measure is computed, each keypoint's trajectory is cleaned:

1. **Confidence filter**: points below the *keypoint confidence* (0.30) are treated as missing.
2. **Gap filling**: gaps up to *fill gaps up to* (0.25 s) are interpolated linearly. Longer gaps stay missing.
3. **3-point median filter**: removes single-frame jumps (for example a paw label briefly jumping to the other paw).
4. **Centered moving average** over *position smoothing* (0.10 s; 0.03 s for gait, so short swing phases are kept).

## Body length

**Body length (BL)** is the median nose–tail-base distance over the video. All speed and distance thresholds are expressed in BL, so the same settings work at different zoom levels and for animals of different sizes. If nose and tail base are rarely detected, BL falls back to 1/8 of the shorter frame side, and the result notes it.

## Time base

Keypoint times start at 0 at the first decoded frame. The review player converts between the video's own timeline and this time base, so events, charts and the overlay all line up.

## Limits to keep in mind

- **One mouse per video.** A second animal would confuse the single-detection step.
- **Training domain.** V2 was trained on cylinder videos. Tail suspension and gait are different views, so check the overlay, and consider adding labeled frames from your setup to the training set.
- **Left and right** are the animal's sides as labeled in training. If your view is mirrored, use *Swap left/right*.
