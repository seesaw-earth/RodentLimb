# What is RodentLimb?

RodentLimb is an iPhone app for **limb-level analysis of mouse behavior videos**. A pose model finds seven body points in every frame. The app then scores three widely used motor and behavior tests:

- **[Tail suspension](../assays/tail-suspension.md)**: immobility, latency, bouts, tail climbing and hindlimb clasping.
- **[Cylinder test](../assays/cylinder.md)**: forelimb use during rearing (left, right, both) and its asymmetry.
- **[Gait analysis](../assays/gait.md)**: stance and swing of each paw, stride, duty factor, base of support, interlimb coordination and gait pattern.

It belongs to the same family as **RodentFlow** (centroid tracking and statistics) and **RodentPose** (whole-body pose for open-field and maze assays).

## The seven keypoints

| Keypoint | Color in the app |
|---|---|
| Left forepaw (LF) | <span class="paw lf"></span>blue |
| Right forepaw (RF) | <span class="paw rf"></span>red |
| Left hind paw (LH) | <span class="paw lh"></span>green |
| Right hind paw (RH) | <span class="paw rh"></span>violet |
| Tail base | <span class="paw tb"></span>pink |
| Nose | <span class="paw nose"></span>amber |
| Mouth | <span class="paw mouth"></span>light blue |

Left and right refer to the **animal's** body. If your camera mirrors the image, use **Swap left/right** in [Parameters](./parameters.md).

## What makes it different

- **Runs once, re-analyze freely.** Pose detection runs once per video. All thresholds, analysis windows and calibration can be changed afterwards, and results update immediately.
- **Everything is in body lengths.** Distances and speeds are scaled to the animal's own nose–tail-base length, so settings carry over between cameras and zoom levels. A cm scale is optional.
- **You can check every number.** The review player draws the keypoints on the video. For the cylinder test, every contact can be replayed and relabeled.
- **Export-ready.** CSV files and a methods paragraph with your exact parameters and references, always in English.
- **Private.** No account, no network, no analytics. See the [privacy policy](../privacy.md).

## Requirements

iPhone or iPad with **iOS 17 or later**. Interface languages: English and Simplified Chinese (switch in Settings).

::: tip Research use
Automated scores support, but do not replace, blinded review of the video. Validate each setup against manual scoring before drawing conclusions; see [Validation](../principles/validation.md).
:::
