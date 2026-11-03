# Model provenance

RodentLimb 1.4.2 ships two Core ML pose models, in the Mac and in the iPhone / iPad app. Their
training data, training runs, test results and what to cite are documented on the website:
https://seesaw-earth.github.io/RodentLimb/models/

| Model | File | Use for |
|---|---|---|
| CylinderPose7 (default) | `CylinderPose7_FP16_640.mlpackage` (19 MB) | Ordinary room light |
| PalmReaderPose8 | `PalmReaderPose8_640_W8A16.mlpackage` (9.8 MB) | Near-infrared, dark box, filmed from below |

## Why the weights are not in this repository

The weights are distributed inside the apps only. They are not committed here, and not attached to
releases, until the redistribution of models derived from the training videos and labels has been
confirmed with their owners:

| Question | State |
|---|---|
| CylinderPose7: training videos and labels may be redistributed in derived form | To confirm with the laboratory that recorded them |
| PalmReaderPose8: terms of the Barkai et al. (2025) training set (Zenodo 10.5281/zenodo.16321240) for derived models | To confirm against the Zenodo record's licence |

To build the apps with the models, install them locally (they stay out of git, see `.gitignore`):

```bash
python3 Tools/install_model.py     --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
python3 Mac/tools/install_model.py --fp16 CylinderPose7_FP16_640.mlpackage.zip --nir PalmReaderPose8_640_W8A16.mlpackage.zip
```

Earlier versions used `CylinderMousePoseV2` (the same network as CylinderPose7 in full precision).
It is no longer included; videos tracked with it keep their keypoints and are labelled with its name
in exports.
