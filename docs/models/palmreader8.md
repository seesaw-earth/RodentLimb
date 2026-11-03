# PalmReaderPose8 (near-infrared)

<p class="rf-eyebrow">DARK-BOX MODEL · YOLO26s-POSE · 8 KEYPOINTS · 8-BIT WEIGHTS</p>

PalmReaderPose8 tracks a mouse filmed from below through a glass floor under near-infrared light, in the dark: the recording setup of the *Palmreader* / Blackbox-style platforms. It is a YOLO pose model trained on the human-labelled frames of a published DeepLabCut training set from that setup.

## Model card

<table class="rf-kv">
<tr><th>Shipped file</th><td><code>PalmReaderPose8_640_W8A16.mlpackage</code> (9.8 MB); metadata: <em>PalmReader mouse pose: 8 keypoints, tailtip excluded</em></td></tr>
<tr><th>Keypoints (output order)</th><td><code>tailbase</code>, <code>centroid</code>, <code>neck</code>, <code>snout</code>, <code>hlpaw</code>, <code>hrpaw</code>, <code>flpaw</code>, <code>frpaw</code> (left/right hind paw, left/right fore paw). The source project's ninth point, <code>tailtip</code>, was left out of training and of the model.</td></tr>
<tr><th>Used by RodentLimb</th><td>Snout (stored as nose), tail base and the four paws. Body centre and neck are not stored; there is no mouth point.</td></tr>
<tr><th>Architecture</th><td>Ultralytics YOLO26s-pose, started from the COCO-pretrained <code>yolo26s-pose.pt</code>, head changed to 8 keypoints; 9,834,519 parameters</td></tr>
<tr><th>Input / output</th><td>640 × 640 RGB image (letterboxed, padding value 114) → raw head tensor (1, 29, 8400): 4 box values, 1 mouse score, 8 × (x, y, confidence); no NMS inside the model</td></tr>
<tr><th>Training data</th><td>409 human-labelled frames from the DeepLabCut project published by Barkai et al. (2025), Zenodo <a href="https://doi.org/10.5281/zenodo.16321240">10.5281/zenodo.16321240</a> (project <code>palmreader-500-AlexZ-2021-03-25</code>)</td></tr>
<tr><th>Labels</th><td>Human annotation only. No DeepLabCut predictions (pseudo-labels) were used.</td></tr>
<tr><th>Software</th><td>Ultralytics 8.4.198, PyTorch 2.11.0, coremltools 9.0, NumPy 2.3.5</td></tr>
<tr><th>Training run</th><td><code>20261102_194842_palm8</code> (notebook <code>PalmReader_YOLO26_8Keypoints_NoTailtip_Colab</code>); evaluation and export run <code>20261102_204957_reuse</code> (notebook <code>PalmReader_Pose8_Train_Export_v3_1</code>)</td></tr>
<tr><th>Weights checksum</th><td>SHA-256 of the trained PyTorch checkpoint: <code>88220bb1a9594ccb2e0e99a072f19ec32fcb906cd413f1bb1f6b2b8edbee3d0d</code></td></tr>
<tr><th>Export</th><td>Core ML ML Program, <code>quantize=8</code>: 8-bit palettized weights with half-precision (FP16) computation, <code>nms=None</code>; 3 November 2026</td></tr>
<tr><th>Licence field in the package</th><td>AGPL-3.0 (written by Ultralytics on export)</td></tr>
</table>

## The source: Palmreader and BAREfoot

The *Palmreader* platform records freely moving mice in the dark from below, with near-infrared light, so that both the paw contacts with the floor and the whole-body pose are visible (Zhang et al., 2022). Barkai et al. (2025) built on these recordings in *BAREfoot*, a machine-learning tool that combines DeepLabCut pose estimation with light-based measures of paw contact to classify pain behaviors. They published their DeepLabCut bottom-up mouse tracking model and its training set on Zenodo.

In that work, mice were filmed at 25 Hz from 30 cm below a glass floor with a near-infrared camera, lit by 850 nm LED strips; videos were recorded at 1000 × 1000 pixels and down-sized to 500 × 500 for analysis. About 50 frames per mouse were labelled with nine body parts: snout, neck, the four paws, body centre, tail base and tail tip.

PalmReaderPose8 re-uses only the **human-labelled frames** of that training set. It does not contain or reproduce the DeepLabCut network.

## Step 1 · Reading the labels

- The labels were read from the project's `CollectedData` files, one annotator ("scorer") per folder; the original Windows paths in the project were not needed.
- Tail tip was dropped, leaving eight points. Frames with fewer than six labelled points, and exact duplicates, were skipped (64 frames), leaving **409 frames**.
- Valid human points per keypoint: tail base 409, body centre 409, neck 332, snout 385, left hind paw 409, right hind paw 409, left fore paw 376, right fore paw 388. Missing points were masked in training, not treated as known occlusions.
- Bounding boxes were derived from the visible keypoints with padding.

## Step 2 · Splits by recording

Frames were split by **recording group**, never by frame: an original video and its down-sized copies (`downsized_`, `downsampled_`, `resized_` prefixes) count as one group. 15 groups were found.

| Split | Frames | Recording groups |
|---|---|---|
| Train | 319 | 11 |
| Validation | 53 | 2 |
| Test | 37 | 2 |

No image appears in two splits (checked by pixel hash). The splits are by recording, not by animal: the published project does not say which recordings come from the same mouse, so the same animal could appear in training and test.

## Step 3 · Training

```python
from ultralytics import YOLO

model = YOLO('yolo26s-pose.pt')                      # COCO-pretrained; head becomes 8 × 3
model.train(data='manual8.yaml', imgsz=640, batch=16, epochs=200, patience=40, seed=42,
            optimizer='AdamW', lr0=1e-3, lrf=0.05, cos_lr=True, deterministic=True,
            mosaic=0.0, mixup=0.0, fliplr=0.0, flipud=0.0,   # no mosaic, mixup or mirroring
            degrees=25, translate=0.1, scale=0.25, hsv_h=0.0, hsv_s=0.0, hsv_v=0.15)
```

Mirroring was switched off because left and right paws must keep their identity. Training stopped early after 108 epochs; the best checkpoint (epoch 68) was selected on the validation frames, where box and pose mAP50 were 0.995 and pose mAP50-95 0.756. The test frames were not used for any choice.

An optional second stage (DeepLabCut pseudo-labels, as for CylinderPose7) was available but did not run: the published project's per-video DeepLabCut predictions were not part of the training input. The shipped model therefore learned from human labels only.

## Step 4 · Evaluation on held-out human labels {#accuracy}

Errors are pixel distances between the model's keypoints and the human labels on the 37 test frames (500 × 500 px images). PCK@*t* is the share of labelled points within *t* body lengths, with the body length taken from the human snout–tail-base distance; frames without that axis (1 of 37) are left out of PCK, and missing or low-confidence predictions count as wrong.

| Test set | Frames | Labelled points | Mouse detected | Median error | 90th percentile | PCK@0.05 | PCK@0.1 |
|---|---|---|---|---|---|---|---|
| 2 held-out recordings | 37 | 291 | 100 % | 9.8 px | 24.4 px | 0.42 | 0.77 |

On the validation frames the median error was 10.4 px (90th percentile 27.3 px). On one further recording (250 × 250 px, 30 fps, 14,905 frames), the mouse was detected in 99.1 % of frames and every keypoint passed a 0.35 confidence threshold in at least 98.8 % of frames; this is a tracking check, not an accuracy measure.

These errors are larger, relative to the animal, than those of CylinderPose7. The training set is small (319 frames), and paws seen from below are small targets. For paw-level measures from near-infrared video, check the overlay carefully.

## Step 5 · Export to Core ML

```python
from ultralytics import YOLO

model = YOLO('PalmReaderPose8.pt')
model.export(format='coreml', imgsz=640, quantize=8, nms=None)   # 8-bit weights, FP16 compute, raw head (1, 29, 8400)
```

The export wrote the eight point names, the input and output layout and the checkpoint checksum into the package metadata, and checked the output shape. A half-precision (FP16) version was exported as well; RodentLimb ships the smaller 8-bit-weight version. 8-bit palettized weights reduce the size; computation still runs in half precision.

::: warning Not yet verified on device
The package metadata records `runtime_verified: false`: the accuracy of the Core ML package on a Mac has not been compared with the PyTorch model on the held-out frames. Before using it for a study, run a few near-infrared videos, check that the keypoints sit on the paws, tail base and snout in the processing queue's live view and the QC player, and compare with the visible-light model if your videos allow it.
:::

## Limitations

- One setup: bottom-up near-infrared video of a single mouse on a glass floor, in the dark. Other cameras, resolutions, floor materials or lighting are untested.
- 37 test frames from 2 recordings; the numbers carry wide uncertainty.
- Splits are by recording, not by animal.
- No mouth point: tasks that need the mouth (paw licking, face grooming) use the snout instead.
- The model knows nothing of paw luminance (paw contact force), which Palmreader and BAREfoot measure from the same video; RodentLimb uses keypoints only.

## Sources

Package metadata; notebooks `PalmReader_YOLO26_8Keypoints_NoTailtip_Colab` (data, training, evaluation) and `PalmReader_Pose8_Train_Export_v3_1` (re-evaluation and Core ML export); Barkai et al. (2025) methods and key resources table; app source `Core/PoseModels.swift`. What to cite: [How to cite](./cite.md#palmreaderpose8).
