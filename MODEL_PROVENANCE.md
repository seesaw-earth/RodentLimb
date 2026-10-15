# Model provenance — CylinderMousePoseV2

| Field | State |
|---|---|
| File | `RodentLimb/Models/CylinderMousePoseV2.mlpackage` (installed locally with `Tools/install_model.py`, not committed) |
| Architecture | Ultralytics YOLO pose (Stage A, 640 × 640 input), raw 7-keypoint head exported to Core ML (nms=False) |
| Keypoints | L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth (`cylinder_DLC/config.yaml`) |
| Training | Distilled from a DeepLabCut model on cylinder-test videos (Colab run `20261014_1156_dlc_distill`) |
| Selected over V1 | Side-by-side A/B comparison on the same videos (CylinderPose dual-model app, Oct 2026) |
| Model owner | **TO CONFIRM** |
| Training videos: owner, consent, redistribution | **TO CONFIRM** |
| Pretrained weights used | **TO CONFIRM** |
| Per-keypoint accuracy on held-out frames | **TO ADD** |
| Accuracy on tail-suspension and gait views | **TO ADD** (outside the training domain) |

Before publishing the weights (for example as a GitHub release asset), confirm that the training videos and labels may be redistributed in derived form.
