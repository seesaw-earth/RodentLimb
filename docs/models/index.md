# Pose models & provenance

RodentLimb finds body keypoints with a pose model that runs on the Mac through Core ML, once per video. Two models ship with RodentLimb for Mac; you choose one per video when you import it, by the lighting of the recording.

| | [CylinderPose7](./cylinderpose7.md) | [PalmReaderPose8](./palmreader8.md) |
|---|---|---|
| **Use for** | Ordinary room light (color or grayscale), usually from below a clear floor | Near-infrared light in the dark, filmed from below (dark-box / Blackbox-style rigs) |
| **Choice in the app** | *Visible light — default* | *Near-infrared, dark box* |
| **File** | `CylinderPose7_FP16_640.mlpackage` (19 MB) | `PalmReaderPose8_640_W8A16.mlpackage` (9.8 MB) |
| **Network** | Ultralytics YOLO26s-pose, 640 × 640 input | Ultralytics YOLO26s-pose, 640 × 640 input |
| **Keypoints** | 7: left/right fore paw, left/right hind paw, tail base, nose, mouth | 8: tail base, body centre, neck, snout, left/right hind paw, left/right fore paw |
| **Training data** | A laboratory's cylinder-test recordings: 543 human-labelled frames and 20,000 cleaned DeepLabCut pseudo-labels | 409 human-labelled frames from the DeepLabCut training set published with Barkai et al. (2025), Zenodo 10.5281/zenodo.16321240 |
| **Test result** | 80 held-out human-labelled frames: mean error 0.035 body lengths, 96 % of points within 0.1 body lengths | 37 held-out human-labelled frames: median error 9.8 px, 77 % of points within 0.1 body lengths |
| **Precision in the app** | Half-precision (FP16) weights | 8-bit palettized weights, FP16 compute |
| **Licence field in the package** | AGPL-3.0 (written by Ultralytics on export) | AGPL-3.0 (written by Ultralytics on export) |

The two test results are not comparable with each other: different videos, frame sizes and numbers of keypoints. Each model page explains how its numbers were obtained.

## One format for every video

Whatever the model, RodentLimb stores the same seven keypoints for every video (`pose.bin`): the four paws, the tail base, the nose and the mouth. All tasks, quality control, review and exports therefore work the same way.

- **CylinderPose7** produces exactly these seven points.
- **PalmReaderPose8** produces eight. Its snout is stored as the nose, and its four paws and tail base keep their names. Its body centre and neck are not stored. It has **no mouth point**, so the mouth stays missing; where a task needs the mouth (paw licking, face grooming), it uses the nose instead, as it does whenever the mouth is not tracked.

Which model tracked a video is recorded with the video and written into every export: the `pose_model` column of `qc_videos.csv`, the export manifest and the first sentence of the methods paragraph. Track all videos of one study with the same model.

## Earlier videos and the iPhone app

Before version 1.3.5, the visible-light model was `CylinderMousePoseV2`, the same trained network stored in full precision (FP32, 38 MB). CylinderPose7 is that network with half-precision weights: across all 104 weight tensors the largest relative difference is 0.044 %, so keypoints differ by rounding only. Videos tracked earlier, on the Mac or on the iPhone, keep their keypoints and are labelled `CylinderMousePoseV2` in exports.

## How a model runs in the app

Every decoded frame is letterboxed to 640 × 640 by Apple's Vision framework, the model returns candidate detections, the most confident mouse is kept (one mouse per video), and its keypoints are mapped back to the original frame. Keypoints below the confidence threshold are treated as missing. Details are in [Pose estimation & cleaning](../principles/pose.md).

## Licences and reuse

- Both packages were trained and exported with Ultralytics YOLO, which is licensed under AGPL-3.0 unless an Ultralytics Enterprise licence applies; the licence field that Ultralytics writes into each package reads AGPL-3.0.
- CylinderPose7 was trained on one laboratory's recordings; whether those recordings are published is stated on its page.
- PalmReaderPose8 was trained on a published DeepLabCut training set; its licence terms are those of the Zenodo record.
- A model being available inside an app does not by itself grant rights to redistribute it or its training data.

See also [Legal & notices](../legal.md) and [How to cite](./cite.md).

::: warning Validate on your own videos
Test scores describe agreement with human labels on held-out frames from the training laboratories. They do not validate the behavioral measures. Before relying on a model for a study, check the keypoint overlay on your own videos and compare the scored measures with manual scoring. See [Validation & limits](../principles/validation.md).
:::
