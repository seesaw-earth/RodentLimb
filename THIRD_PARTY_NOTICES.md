# Third-party software and redistribution review

## Application code

RodentLimb's source code is distributed under the GNU AGPL-3.0 (see `LICENSE`), the same as RodentPose. The project uses no third-party Swift packages; it relies only on Apple system frameworks (SwiftUI, Swift Charts, Core ML, Vision, AVFoundation, PhotosUI), which are governed by Apple's developer terms.

## Pose model

`CylinderMousePoseV2` was trained and exported with Ultralytics YOLO, distilled from a DeepLabCut model. Ultralytics offers AGPL-3.0 and enterprise licensing (https://www.ultralytics.com/license). Distributing the app binary with the model therefore needs to satisfy those terms; the AGPL-3.0 license of this repository and the public source code are intended to do that. The weights are not committed here; see `MODEL_PROVENANCE.md`.

## Manual website

The manual is built with VitePress (MIT License) and published with GitHub Pages.

## Not legal advice

This file lists the known third-party components and open questions. It is not legal clearance.
