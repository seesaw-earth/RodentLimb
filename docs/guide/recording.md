# Recording videos

The model finds paws best when they are large, sharp and evenly lit. A few minutes spent on the camera setup saves hours of checking later.

## Choose the model by the light

| Your recording | Pose model to choose at import |
|---|---|
| Room light, color or grayscale, usually from below a clear floor | **Visible light** — [CylinderPose7](../models/cylinderpose7.md) (default) |
| In the dark, under near-infrared light, filmed from below a glass floor (dark-box / Blackbox-style rigs) | **Near-infrared, dark box** — [PalmReaderPose8](../models/palmreader8.md) |

Track all videos of one study with the same model.

## For all tasks

- **One mouse per video**, fully in view for the whole recording. If several chambers are filmed together, crop each chamber into its own video first.
- **Fixed camera** on a tripod or rig. Do not zoom or move it during the session. A fixed camera also lets you reuse one calibration for every video.
- **Even, diffuse light**, no moving shadows. Avoid glare on acrylic.
- **Fill the frame** with the apparatus. The more pixels per paw, the better.
- **Sharp frames**: a shutter fast enough to freeze paw movement. In dim light, add light rather than letting the camera lengthen the exposure.
- **Frame rate**: at least 25–30 fps; fast behaviors (scratching, flinching, gait) need 60 fps or more.

## File formats

RodentLimb reads videos through macOS (AVFoundation): MP4 and MOV with H.264 or HEVC work directly, including iPhone recordings. The import table checks each file and marks those the Mac cannot decode, for example:

- **AVI, MKV** and other containers macOS does not open;
- **AV1** on Macs without an AV1 decoder (M1 and M2), and VP8 / VP9.

Convert such files to H.264 MP4 first, for example with ffmpeg:

```bash
ffmpeg -i input.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -an output.mp4
```

## Per task

| Task | Camera | Length | Notes |
|---|---|---|---|
| [Tail suspension](../assays/tail-suspension.md) | Front (ventral) or back (dorsal) of the hanging mouse, both hind paws visible | 6 min from suspension | Climb-stoppers reduce tail climbing in strains such as C57BL/6 |
| [Cylinder](../assays/cylinder.md) | From below through a clear floor (best); side view also works | 5–10 min, or about 20 rears | Avoid mirrors behind the cylinder |
| [Gait](../assays/gait.md) | From below a straight walkway with a clear floor | Several crossings | ≥ 60 fps (120–240 fps is better); a ruler in view once for cm |
| [Itch](../assays/itch.md) | From below through a clear floor, one mouse per chamber | 30–60 min from the injection | ≥ 30 fps, 60 fps better; set the injection time |
| [Spontaneous pain](../assays/pain.md) | From below, injected paw visible | Formalin 45–60 min, capsaicin 5–10 min | ≥ 30 fps; set the injected paw and the injection time |
| [Self-grooming](../assays/grooming.md) | From below, one mouse | 10 min after a short habituation; splash test right after the spray | ≥ 30 fps |
| [Seizure](../assays/seizure.md) | From below through a clear floor or cylinder | From before the injection to ≥ 30 min after | ≥ 30 fps; confirm every event on the video |

If a video starts before the injection, set the **injection time** in the analysis parameters; latencies, phases and time bins are measured from it.

::: tip The visible-light model was trained on cylinder videos
CylinderPose7 learned from cylinder-test footage seen from below. For other tasks and views, check the keypoint overlay on a few videos before scoring a whole study. If paw tracking is poor, labelled frames from your own setup are the most effective fix.
:::
