---
outline: [2, 2]
---

# Legal & notices

## Licence

RodentLimb's source code is distributed under the **GNU Affero General Public License v3.0** ([LICENSE](https://github.com/seesaw-earth/RodentLimb/blob/main/LICENSE)). You may use, study, modify and share it under the terms of that licence. The app is offered free of charge on the App Store; your use of the App Store version is also governed by Apple's [Licensed Application End User License Agreement](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

© 2026 Ziqing Shi.

## Pose models

The pose models are trained and exported with [Ultralytics YOLO](https://github.com/ultralytics/ultralytics), which is available under the AGPL-3.0 or an Ultralytics enterprise licence. The model files are not in the source repository; their provenance, training data and licences are described on the model pages:

- [CylinderPose7](./models/cylinderpose7.md) — trained on labelled cylinder-test frames and distilled from a DeepLabCut model.
- [PalmReaderPose8](./models/palmreader8.md) — trained on the human-labelled frames of the published DeepLabCut training set of Barkai et al. (2025), Zenodo record [10.5281/zenodo.16321240](https://doi.org/10.5281/zenodo.16321240). Please also cite that work if you use this model; see [How to cite](./models/cite.md).

## Third-party software

| Component | Used for | Licence |
|---|---|---|
| Apple system frameworks (SwiftUI, Swift Charts, Core ML, Vision, AVFoundation) | The app | Apple developer terms |
| Ultralytics YOLO | Training and exporting the pose models | AGPL-3.0 |
| coremltools | Converting the models to Core ML | BSD-3-Clause |
| DeepLabCut | Labelling projects behind the training data | LGPL-3.0 |
| VitePress | This website | MIT |

The app uses no third-party Swift packages, analytics or advertising SDKs.

## Research use only

RodentLimb is a research tool for laboratory animal studies. It is not a medical device and is not intended for diagnosis or treatment of humans or animals.

Results are computed automatically from keypoints and depend on your videos, the pose model and the parameters you choose. Check them against manual scoring on your own setup (see [Validation](./principles/validation.md)) before you rely on them. The software is provided **as is, without warranty of any kind**, as set out in sections 15 and 16 of the AGPL-3.0.

## Animal research

RodentLimb analyses videos; it does not replace the approvals, ethical review and welfare standards that apply to your work. Follow your institution's animal care and use requirements, and report your experiments according to the [ARRIVE 2.0](https://arriveguidelines.org/) guidelines.

## Trademarks

Apple, Mac, macOS, iPhone, iPad, App Store and Core ML are trademarks of Apple Inc. Other product names are the property of their owners. RodentLimb is not affiliated with or endorsed by Apple, Ultralytics or the DeepLabCut project.

## Contact

[github.com/seesaw-earth/RodentLimb/issues](https://github.com/seesaw-earth/RodentLimb/issues) · [Support](./support.md) · [Privacy](./privacy.md)
