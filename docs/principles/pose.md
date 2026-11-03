# Pose estimation & cleaning

## The models

Every video is tracked once by a pose model that finds the mouse and its keypoints in each frame. RodentLimb for Mac ships two models; you choose one per import (and can re-track a video with the other from its page):

| Choice at import | Model | Keypoints from the model | Use for |
|---|---|---|---|
| **Visible light** (default) | [CylinderPose7](../models/cylinderpose7.md) — YOLO26s-pose, FP16 Core ML | 7: nose, mouth, tail base, four paws | Room-light recordings |
| **Near-infrared, dark box** | [PalmReaderPose8](../models/palmreader8.md) — YOLO26s-pose, 8-bit weights | 8: snout, neck, body centre, tail base, four paws | Bottom-up near-infrared recordings in the dark |

Whatever the model, RodentLimb stores the same **seven keypoints** for every video — left and right fore and hind paws (LF, LH, RF, RH), tail base, nose and mouth — so every analysis and export works with either. PalmReaderPose8's snout is stored as the nose; its neck and body-centre points are not stored. Use one model for all videos of a study.

Videos tracked by RodentLimb for iPhone, or by earlier Mac versions, are labeled *CylinderMousePoseV2*, the original FP32 model. Their keypoints stay valid and are analyzed the same way.

## From frames to keypoints

For every frame of the video:

1. macOS decodes the frame (AVFoundation) and the video's rotation is applied, so positions match what you see in the player.
2. The frame is letterboxed to the model's square input (640 × 640) by Vision and run on the Neural Engine, GPU or CPU (Settings → *Processors*).
3. The model returns candidate detections. The most confident one above the **detection threshold** (Settings, default 0.25) is kept, since there is one mouse per video. Frames below it count as “no mouse”.
4. The keypoints of that detection are mapped back to the original frame, each with its confidence.

The keypoints are saved once per video in `pose.bin`, with the model name and version. Nothing after this step needs the model again, so changing an analysis parameter is instant. Tracking saves a checkpoint every couple of seconds; a stopped or interrupted run continues where it left off.

## Cleaning

Before any measure is computed, each keypoint's trajectory is cleaned. The settings are under *Untracked frames & pose cleaning (advanced)* in each analysis's parameters and are written into the methods text:

1. **Confidence filter.** Points below the *keypoint confidence* (0.30) are treated as missing.
2. **Implausible jumps** (off by default). A point farther than the *jump threshold* (0.5 BL) from the median of its tracked neighbours within ±0.1 s becomes a gap (a Hampel-style filter; twice the threshold at the edges of gaps, where the median lags behind a fast paw).
3. **Gap filling.** Gaps up to *fill gaps up to* (0.25 s) are filled; longer gaps stay missing and are excluded from every measure, because reconstructing seconds of movement would invent behavior that was never seen. Methods:
   - **Linear** (default; the method the analyzers were validated with) — a straight line between the frames before and after the gap;
   - **Cubic (shape-preserving)** — a monotone cubic Hermite curve (Fritsch–Carlson) that keeps the direction of motion and never overshoots;
   - **Body-relative** — the paw's position relative to the body axis (tail base → nose) is interpolated and moved with the body, for paws hidden briefly while the mouse walks or turns;
   - **Kalman smoother** — a constant-velocity Kalman filter with a Rauch–Tung–Striebel smoother, using the motion on both sides of the gap.
4. **3-point median filter** removes single-frame jumps (for example a paw label briefly jumping to the other paw).
5. **Centered moving average** over *position smoothing* (0.10 s; 0.03 s for gait, so short swing phases are kept).

The numbers of filled frames, long gaps and removed jumps are reported in [Quality control](../guide/qc.md).

## Body length

**Body length (BL)** is the median nose–tail-base distance over the video. Speed and distance thresholds are expressed in BL, so the same settings work at different zoom levels and for animals of different sizes. If nose and tail base are rarely detected, BL falls back to 1/8 of the shorter frame side, and the result notes it.

## Time base

Keypoint times start at 0 at the first decoded frame. The review player converts between the video's own timeline and this time base, so events, charts and the overlay line up. Latencies and time bins of the behavior tasks are measured from the *injection time* you set.

## Limits to keep in mind

- **One mouse per video.** A second animal would confuse the single-detection step.
- **Training domain.** CylinderPose7 learned from cylinder-test videos filmed from below, and PalmReaderPose8 from one near-infrared dark-box setup. Other views and setups can work, but check the keypoint overlay on a few videos before scoring a study.
- **Left and right** are the animal's sides as labeled in training. If your view is mirrored, use *Swap left/right labels* (cylinder, gait).
- **Keypoints, not contact.** Paw contact area, pressure and weight bearing cannot be measured from keypoints.
