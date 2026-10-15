# Parameters

Pose detection runs once. Everything after that is computed from the stored keypoints, so every parameter below can be changed at any time. Results update as you move a slider; the key numbers at the top of the sheet show the effect immediately.

## Keeping a study consistent

- **Apply to all sessions of this assay…** copies the current parameters to every session of the same assay. The cylinder lesion side is kept per animal.
- **Reset to defaults** returns to the defaults below.
- New sessions start with the parameters of the last session of the same assay.
- The values used are written into each session's **methods** export.

## Distances are in body lengths

Speeds and distances are expressed in **body lengths (BL)**: the median nose–tail-base distance over the video. Thresholds therefore transfer between cameras and zoom levels. For a typical adult mouse, 1 BL ≈ 8–9 cm.

## Assay parameters

The parameters of each assay are explained on its page:

- [Tail suspension](../assays/tail-suspension.md#parameters)
- [Cylinder test](../assays/cylinder.md#parameters)
- [Gait analysis](../assays/gait.md#parameters)

## Pose cleaning (advanced)

Shared by all assays; see [Pose model & cleaning](../principles/pose.md).

| Parameter | Default | Meaning |
|---|---|---|
| Keypoint confidence | 0.30 | Keypoints below this confidence are treated as missing. |
| Fill gaps up to | 0.25 s | Shorter gaps are linearly interpolated. |
| Position smoothing | 0.10 s (gait 0.03 s) | Centered moving average after a 3-point median filter. |

## App settings

In **Settings**:

- **Detection confidence** (default 0.25): a minimum score to accept the mouse detection. Lower it if the mouse is often missed. It applies to the next pose detection.
- **Also render skeleton video**: writes an MP4 with the skeleton drawn in. It is only needed for sharing and makes detection slower.
