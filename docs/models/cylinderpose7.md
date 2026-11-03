# CylinderPose7 (visible light)

<p class="rf-eyebrow">DEFAULT MODEL · YOLO26s-POSE · 7 KEYPOINTS · FP16</p>

CylinderPose7 tracks the paws, nose, mouth and tail base of a mouse in ordinary room-light video. It is a YOLO pose model that learned from a few hundred human-labelled frames and twenty thousand carefully cleaned DeepLabCut predictions of the same laboratory's cylinder-test recordings, then was exported to Core ML with half-precision weights.

## Model card

<table class="rf-kv">
<tr><th>Shipped file</th><td><code>CylinderPose7_FP16_640.mlpackage</code> (19 MB); metadata: <em>CylinderMousePose V2 FP16</em>, model version 2.1, precision FP16</td></tr>
<tr><th>Same network as</th><td><code>CylinderMousePoseV2</code> (FP32, 38 MB, model version 2.0), used by the iPhone app and by the Mac app before 1.3.5</td></tr>
<tr><th>Keypoints (output order)</th><td><code>L_fore_paw</code>, <code>L_hind_paw</code>, <code>R_fore_paw</code>, <code>R_hind_paw</code>, <code>tail_base</code>, <code>nose</code>, <code>mouth</code> (the order of the laboratory's DeepLabCut project)</td></tr>
<tr><th>Architecture</th><td>Ultralytics YOLO26s-pose, started from the COCO-pretrained <code>yolo26s-pose.pt</code>; 9,783,360 parameters</td></tr>
<tr><th>Input / output</th><td>640 × 640 RGB image → raw head tensor (1, 26, 8400): 4 box values, 1 mouse score, 7 × (x, y, confidence); no NMS inside the model</td></tr>
<tr><th>Training data</th><td>543 human-labelled frames (used twice) + 20,000 cleaned DeepLabCut pseudo-labels from 506 recordings</td></tr>
<tr><th>Teacher model</th><td>DeepLabCut ResNet-50 model <code>DLC_resnet50_cylinder_DLCJan2shuffle1_44000</code></td></tr>
<tr><th>Software</th><td>Ultralytics 8.4.177, PyTorch 2.11.0, coremltools 9.0</td></tr>
<tr><th>Training run</th><td><code>20261014_1156_dlc_distill</code> (notebook <code>Cylinder_YOLO26_v2_DLC_Distill</code>)</td></tr>
<tr><th>Export</th><td>Core ML ML Program, <code>quantize=16</code> (FP16 weights), <code>nms=None</code>; 14 October 2026</td></tr>
<tr><th>Licence field in the package</th><td>AGPL-3.0 (written by Ultralytics on export)</td></tr>
</table>

## Why distil DeepLabCut?

The laboratory already had a DeepLabCut model that had tracked hundreds of cylinder-test videos. DeepLabCut gives accurate, project-specific keypoints, but its ResNet-50 network and Python stack do not fit an offline Mac app. A YOLO pose model exports cleanly to Core ML. Distillation turns the videos DeepLabCut has already tracked into training data for the smaller model. It carries two risks: the student can copy the teacher's mistakes, and many easy, repetitive frames can drown out the hard poses. Each step below addresses one of these.

## The source data

- **Human labels:** 743 labelled frames in 38 `labeled-data` folders of the laboratory's DeepLabCut project.
- **Teacher predictions:** one DeepLabCut track per analysed video. After merging each recording with its down-sized copy there were 524 distinct recordings; 519 had tracks from the teacher model above. Videos were recorded at 60 fps.
- **Availability:** the recordings belong to the laboratory's own project. They are not, as far as these pages establish, publicly released; if they are published (for example as a dataset with a DOI), cite that dataset.

## Step 1 · Splits without leakage

Splits were made over human-labelled *recording groups*, so every test frame is a human label from a recording the model never saw. The original and the down-sized version of a recording count as one group.

| Split | Human-labelled frames | Recording groups | Used for |
|---|---|---|---|
| Train | 543 | 28 | Training |
| Validation | 120 | 6 | Choosing checkpoints and the final model |
| Test | 80 | 4 | Reported results only |

DeepLabCut pseudo-labels were drawn only from recordings outside the validation and test groups.

## Step 2 · Cleaning DeepLabCut trajectories

Each frame is judged in the context of its whole trajectory and dropped if any rule fails:

| Rule | Setting |
|---|---|
| Visibility | Likelihood ≥ 0.95 → visible; < 0.50 → occluded; anything in between → drop the frame, so the model never learns a wrong "not visible" signal |
| Enough points | At least 4 visible points |
| Temporal jumps | A visible point more than 0.15 median body lengths from its 7-frame rolling median |
| Left/right swap | Left and right paws both on the opposite side of the tail-base→nose axis from where they usually are in that video |
| Geometry | Nose–mouth distance ≤ 0.35 body length; body length 0.30–1.60 × the video median; confident points inside the frame |

Of 34,292,020 DeepLabCut frames, these rules kept 24,362,080 (71.0 %).

## Step 3 · Choosing 20,000 frames

1. Candidates: cleaned frames at least 10 frames apart, at most 1,500 per video (752,692 candidates).
2. Pose description: keypoints relative to the tail base, rotated to the body axis and divided by the video's median body length, so rearing and four-paw postures stay distinct.
3. Clustering: k-means with 60 pose clusters, plus one group for frames missing the nose or tail base.
4. Balanced draw: the same quota from every cluster, round-robin across videos, at most 120 frames per video.

## Step 4 · An independent check of the pseudo-labels

A YOLO model trained only on the human labels (M0) predicted every candidate frame. Wherever M0 was confident (≥ 0.5) about a point that lay more than 0.25 body lengths from DeepLabCut's, the frame was rejected and listed for human review. Frames M0 could not handle were kept, so the filter does not bias the set towards easy poses. 903 frames were rejected and 20,000 pseudo-labels remained.

## Step 5 · Training

| Stage | Starts from | Training data | Epochs (patience) | Learning rate |
|---|---|---|---|---|
| M0 · human labels only | `yolo26s-pose.pt` | 543 human frames | 150 (40) | 1e-3 |
| A · pseudo + human (**shipped**) | `yolo26s-pose.pt` | 20,000 pseudo-labels + 543 human frames × 2 | 60 (20) | 1e-3 |
| B · human fine-tune | stage A | 543 human frames | 60 (25) | 2e-4 |

Common settings: 640 px, batch 16, AdamW, cosine learning rate, seed 42, mosaic 0.5, horizontal flip 0.5 with left/right keypoints exchanged, rotation ±10°, translation 0.06, scale 0.25. The final model was chosen by mean keypoint error on the validation frames; stage A had the lowest (0.0339 body lengths).

## Step 6 · Evaluation on human labels {#accuracy}

Errors are measured against human labels and divided by the body length (the human nose–tail-base distance). PCK@*t* is the share of points within *t* body lengths. 95 % confidence intervals come from 2,000 bootstrap resamples.

| Model (80 test frames) | Mean frame error [95 % CI] | Median error | 90th percentile | PCK@0.05 | PCK@0.1 |
|---|---|---|---|---|---|
| M0 · human labels only | 0.0502 [0.040, 0.062] | 4.29 px | 12.93 px | 0.762 | 0.919 |
| **A · shipped** | **0.0346 [0.025, 0.046]** | **2.76 px** | **6.60 px** | **0.919** | **0.956** |
| B · human fine-tune | 0.0349 [0.026, 0.047] | 3.11 px | 6.40 px | 0.923 | 0.958 |
| DeepLabCut teacher (reference, 60 frames) | 0.0211 [0.018, 0.024] | 2.70 px | 5.03 px | 0.965 | 0.995 |

The mouse was detected in every test frame. The paired difference A − M0 was −0.0156 body lengths [−0.019, −0.012]: the pseudo-labels clearly helped. About 6 % of test frames had the left and right paws swapped (6.3 % fore, 6.4 % hind), the same for all three stages. The DeepLabCut teacher was probably trained on these very human-labelled frames, so its numbers are optimistic.

## Step 7 · Export to Core ML in half precision

The shipped package was exported from the stage-A weights with Ultralytics' Core ML exporter, keeping the raw pose head so the app decodes it itself:

```python
from ultralytics import YOLO
import coremltools as ct

exported = YOLO('CylinderMousePoseV2.pt').export(
    format='coreml', imgsz=640, quantize=16, nms=None)   # FP16 weights, raw head (1, 26, 8400)

m = ct.models.MLModel(exported, skip_model_load=True)    # edit metadata only
m.short_description = 'CylinderMousePose V2 FP16 - YOLO26s-Pose, DLC distilled, 7 keypoints'
m.version = '2.1'
m.user_defined_metadata.update({'model_family': 'CylinderMousePose', 'model_version': '2.1',
    'precision': 'FP16', 'input_size': '640', 'source_run': '20261014_1156_dlc_distill'})
m.save('CylinderMousePoseV2.mlpackage')
```

The package was then renamed `CylinderPose7_FP16_640.mlpackage`. Half-precision weights halve the size (19 MB instead of 38 MB); the 104 weight tensors match the full-precision model within 0.044 % (largest relative difference), and the Mac's Neural Engine computes in half precision anyway.

## Limitations

- One laboratory, one rig, one camera setup. Other cylinders, lighting, frame rates or strains are untested.
- The test set is 80 frames from 4 recording groups; the confidence intervals are correspondingly wide.
- About 6 % of test frames have left/right paws swapped. Review paw identity before reporting asymmetry.
- Pseudo-labels inherit DeepLabCut's systematic biases; the agreement filter only removes clear disagreements.
- The model was trained on cylinder-test videos. RodentLimb also uses it for tail suspension, gait, itch, pain, grooming and seizure videos; these are outside its training data. Check the overlay before scoring.
- No comparison of derived scores (such as wall contacts or scratching bouts) with human scoring is reported here.

## Sources

Package metadata; notebooks `Cylinder_YOLO26_v2_DLC_Distill` (training, evaluation and FP16 export) and `Cylinder_YOLO26_Pose_Training` (version 1, superseded); app source `Core/PoseModels.swift`. What to cite: [How to cite](./cite.md#cylinderpose7).
