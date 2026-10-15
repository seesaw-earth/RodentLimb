# Recording videos that track well

The model finds paws best when they are large, sharp and evenly lit. A few minutes spent on the camera setup saves hours of checking later.

## For all assays

- **One mouse per video**, fully in view for the whole recording.
- **Fixed camera** on a tripod or rig. Do not zoom or move it during the session. A fixed camera also lets you reuse one calibration for every video.
- **Even, diffuse light**, no moving shadows. Avoid glare on acrylic.
- **Fill the frame** with the apparatus. The more pixels per paw, the better.
- **Sharp frames**: a shutter fast enough to freeze paw movement. In dim light, add light rather than letting the camera lengthen the exposure.
- **Common formats**: iPhone recordings (HEVC or H.264, MOV or MP4) work directly.

## Tail suspension

- Film the hanging mouse **from the front (ventral) or back (dorsal)** so both hind paws are visible. Hindlimb clasping cannot be judged from the side.
- Start recording at the moment of suspension. A standard test lasts **6 minutes**; immobility is usually scored over minutes **2–6**.
- One mouse per chamber and per video. Climb-stoppers (a small tube around the tail base) reduce tail climbing in strains such as C57BL/6.

## Cylinder test

- **Bottom view** through a transparent floor works best. A paw on the wall then appears at the rim of the circle.
- A **side view** also works; you then mark the floor line instead.
- A typical cylinder for mice is about 9–10 cm wide and 15 cm high. Record **5–10 minutes**, or until about 20 rears.
- Mirrors behind the cylinder help a human scorer but confuse the model. Prefer a single direct view.

## Gait analysis

- **Bottom (ventral) view** of a straight walkway with a clear floor.
- **High frame rate.** Stance and swing last tens of milliseconds, so use **60 fps or more** (120 or 240 fps is better). At 30 fps, timing is resolved only to 33 ms and duty factor is biased.
- Let the mouse cross several times. Only steady, straight walking is analyzed, so more runs give more strides.
- Put a ruler or a marked distance in view once if you want lengths in cm.

::: tip The model was trained on cylinder videos
CylinderMousePoseV2 was trained on cylinder-test footage. For tail suspension and gait, check the overlay in the review player first. If paw detection is poor, adding labeled frames from your own setup to the training set is the most effective fix.
:::
