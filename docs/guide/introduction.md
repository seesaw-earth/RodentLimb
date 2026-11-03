# What is RodentLimb?

RodentLimb measures mouse behavior at the level of the limbs. A pose model finds the four paws, the tail base, the nose and the mouth in every frame of a video; the app then cleans these trajectories and scores standard tests from them. It runs entirely on your Mac (or iPhone and iPad), without an account or an internet connection.

## What it does

1. **Tracks keypoints** in every frame with a pose model that runs on the device through Core ML. You choose the model by the lighting of the recording: [CylinderPose7](../models/cylinderpose7.md) for room light, [PalmReaderPose8](../models/palmreader8.md) for near-infrared video filmed from below in the dark.
2. **Checks tracking quality** for every video against inclusion criteria you set for the study, and records why a video was excluded.
3. **Scores seven tests** from the same keypoints: tail suspension, cylinder, gait, itch (scratching), spontaneous pain, self-grooming and seizures. Each test reports its measures, the events behind them and a time course.
4. **Lets you review** every detected event on the video and correct its label; the measures update and the edits are counted in the export.
5. **Organizes studies**: factors and groups, timepoints, animals, randomized allocation and blinding, with group summaries in which the animal is the unit.
6. **Exports** long-format tables for R, Python, SPSS or Prism, a behavior-segment table, a methods paragraph with your parameters and references, and files for BORIS, DeepEthogram and DeepLabCut-based tools.

## Who it is for

Laboratories that already film mice in these tests and want reproducible, keypoint-based measures without writing analysis code. The model runs once per video; thresholds, time windows and calibration can be changed afterwards and results update immediately, so you can tune the settings to your own manual scoring.

## The Mac app

RodentLimb for Mac is designed for many long videos: drop a folder into the window, let the queue run overnight, then review and export in the morning. Tracking is saved frame by frame, so a pause, a crash, a sleeping laptop or an unplugged drive does not lose work. See [Quick start on Mac](./getting-started.md).

Requirements: macOS 14 Sonoma or later. Apple silicon and Intel Macs are supported; Apple silicon is much faster. Interface: English and Simplified Chinese (switch under **RodentLimb › Language · 语言**). Exports are always in English.

## iPhone and iPad

The iPhone and iPad app shares the analysis code and the library format with the Mac app. A library can be copied from the iPhone to the Mac and opened there. See [iPhone & iPad](./iphone.md).

## What it does not do

- It does not diagnose disease and is not a veterinary or clinical tool.
- It does not replace checking a sample of videos by hand. Default thresholds come from simulated data and published protocols; set them against your own manual scoring before a study. See [Validation & limits](../principles/validation.md).
- It analyses one mouse per video.
- It does not record video, and it does not render videos with the skeleton drawn on them.
