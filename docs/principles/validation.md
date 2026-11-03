# Validation & limits

RodentLimb is a research tool. This page lists what has been checked, and what you need to check on your own videos before using the results in a study.

## Pose models

Each model's accuracy on held-out test frames is on its page:

- [CylinderPose7](../models/cylinderpose7.md#accuracy) — test frames from recordings not used for training.
- [PalmReaderPose8](../models/palmreader8.md#accuracy) — 37 test frames from two held-out recording groups.

Test frames come from the same setups the models were trained on. Accuracy on your camera, lighting and arena can be lower.

## Analysis: simulated mice

The analyzers of the first three tasks were ported line-for-line to Python and run on **simulated mice with known ground truth** (the scripts are in `Tools/validation/` in the repository).

### Gait

Simulated trot, 20 cm/s, 4 Hz, duty factor 0.60, hind base of support 3 cm, 1–2 px keypoint noise:

| Measure | Truth | RodentLimb |
|---|---|---|
| Stride length | 5.00 cm | 5.00 cm |
| Stride frequency | 4.00 Hz | 4.00 Hz |
| Duty factor (100 fps) | 0.60 | 0.59 |
| Duty factor (30 fps) | 0.60 | 0.70 |
| Hind base of support | 3.0 cm | 2.98–3.00 cm |
| Step length (hind) | 25 px | 25.6 px |
| Nose lateral sway | 0.133 BL | 0.129 BL |
| Stride length @ reference speed (mixed speeds) | 50.0 px | 50.2 px |
| Phases LH→RH / LH→RF (trot) | 0.5 / 0 | 0.49–0.52 / 0.00–0.01 |
| Gait pattern (trot) | trot | 26 of 28 strides trot |
| Strides while turning at 40 °/s | rejected | 0 kept |

The stance-detection defaults (step speed = smaller of the backward and forward steps; stance ratio 0.8) were chosen from these simulations. At 30 fps, duty factor is biased by about one frame, and the app warns below 50 fps.

### Tail suspension

Simulated 6-minute test with random mobile / immobile periods, breathing movement during immobility, and 0.8 px noise: immobility **163.5 s vs 165.4 s** true, latency **5.7 s vs 5.6 s**, **99.2 %** frame-level agreement.

### Cylinder test

Simulated bottom-view session with 9 scripted rears (left first, right first, both): **9 / 9** labeled correctly, also with 3 px noise and 20 % of paw detections missing.

### Itch, pain, grooming and seizure

Time windows, phases and bins of these tasks follow the published protocols (see the presets on each task page). The detection thresholds — distances and speeds in body lengths, movement energy — were set on simulated data and have **not yet been validated against manual scoring of real videos**. Treat these four tasks as a first pass: every detected event is listed for review, and the methods text counts how many you edited.

## Software tests

The Mac app's analysis code is the same as the iPhone app's (checked byte by byte). Automated tests of the shared and core layers cover, among others:

- **Interrupted tracking**: a 5,000-frame run stopped at frame 3,100 continues from its checkpoint and gives bit-identical keypoints; `pose.bin` reads back without loss.
- **Batch processing** with a simulated model: pause and resume, a broken file failing with its reason, a retry from the checkpoint, an offline drive waiting in the queue.
- **Export**: every table read back with pandas; segment durations equal end − start; DeepLabCut files read with `header=[0,1,2]` (7 body parts × x, y, likelihood).
- **Pose models**: keypoint mapping of each model (PalmReaderPose8: snout → nose, four paws, tail base, no mouth), output layouts, the model name recorded in `pose.bin`, the QC table and the methods text.
- **Library safety**: Recently Deleted, restore, backups and the library lock.
- **Presets**: each preset can be applied repeatedly, keeps per-animal settings and is recognized.

## What you need to check

Simulations test the **analysis**, not the **pose model** on your videos. Before using the results in a study:

1. **Check the overlay** on a few videos in the review player. Is every keypoint on the right body part, and are left and right correct?
2. **Score a subset by hand**, blinded, for example 10 % of animals, and compare: immobility time, contact counts, stride measures, scratching bouts, licking time, grooming time, seizure stage.
3. **Fix the parameters** that best match your manual scoring, apply them to all sessions of the study (*Apply to…*), and report them (the methods export contains them).
4. **Review the event lists** (cylinder contacts and every behavior task). Corrections are stored and counted.
5. **Set inclusion criteria in advance** ([Quality control](../guide/qc.md)) and exclude videos that fail them.

Report the agreement (for example a correlation or Bland–Altman plot) in your methods.
