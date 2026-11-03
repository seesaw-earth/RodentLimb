---
layout: home
title: RodentLimb
titleTemplate: Limb pose and behavior scoring for mouse videos

hero:
  name: RodentLimb
  text: Limb pose and behavior scoring for mouse videos, on your Mac
  tagline: Track the four paws, nose, mouth and tail base in every frame of long videos, then score seven tests, from tail suspension and gait to itch, pain, grooming and seizures. Everything runs on the Mac; nothing is uploaded.
  image:
    src: /hero.png
    alt: RodentLimb app icon
  actions:
    - theme: brand
      text: Mac App Store
      link: https://apps.apple.com/app/id6822935387
    - theme: alt
      text: Quick start
      link: /guide/getting-started
    - theme: alt
      text: Pose models & provenance
      link: /models/
    - theme: alt
      text: 中文
      link: /zh/

features:
  - title: Two pose models, chosen by the light
    details: CylinderPose7 for ordinary room-light video, PalmReaderPose8 for near-infrared video filmed from below in a dark box. Both run on the Mac with Core ML.
    link: /models/
    linkText: Models & provenance
  - title: Seven tests from one pipeline
    details: Tail suspension, cylinder, gait, itch, spontaneous pain, self-grooming and seizure scoring. Every event can be replayed on the video and relabeled.
    link: /assays/
    linkText: Tasks
  - title: Built for overnight batches
    details: Drop in a folder of videos. A queue tracks them one frame at a time with checkpoints, so a pause, crash or power cut costs seconds, not hours.
    link: /guide/processing
    linkText: Processing queue
  - title: Quality control before scoring
    details: Inclusion criteria are set per study before analysis. Each video gets a pass, warning or fail verdict, and every exclusion keeps its reason.
    link: /guide/qc
    linkText: Quality control
  - title: Studies, blinding and clean exports
    details: Factors, timepoints, randomized allocation and blinding. One long-format table per task, a behavior-segment table, a methods paragraph, and BORIS / DeepLabCut formats.
    link: /guide/export
    linkText: Export
  - title: Private by design
    details: No account, no network connection, no analytics. Videos stay where they are and are only read. English and Simplified Chinese.
    link: /privacy
    linkText: Privacy policy
---

<div class="rf-home">

## How it works

1. **Import.** Drop videos or whole folders into the window. Animal, timepoint and trial are read from the file names, and you pick the pose model that matches the lighting.
2. **Track.** The pose model reads every frame once, in a background queue, and stores the keypoints.
3. **Check.** Each video gets a quality-control verdict against the criteria you set for the study; you include or exclude the rest with a reason.
4. **Score.** Assign one or more tasks. Results update immediately when you change a parameter, because the model never runs again.
5. **Review and export.** Replay every detected event on the video, correct labels, then export tables, behavior segments and a methods paragraph for the whole study.

## Pose models

| Model | For videos filmed | Keypoints used | Trained on |
|---|---|---|---|
| [**CylinderPose7** (default)](./models/cylinderpose7.md) | In ordinary room light, usually from below a clear floor | Four paws, tail base, nose, mouth | A lab's cylinder-test recordings: 543 human-labelled frames and 20,000 cleaned DeepLabCut predictions |
| [**PalmReaderPose8**](./models/palmreader8.md) | From below in the dark, under near-infrared light (dark-box rigs) | Four paws, tail base, snout (stored as nose) | 409 human-labelled frames from the published DeepLabCut training set of Barkai et al. (2025) |

Both are Ultralytics YOLO26s-pose networks with 640-pixel input, exported to Core ML. Where their data came from, how they were trained and tested, and what to cite are on [Models & provenance](./models/).

## Tasks

| Task | Main measures |
|---|---|
| [Tail suspension](./assays/tail-suspension.md) | Immobility time and %, latency, bouts, per-minute profile, tail climbing, estimated clasping score |
| [Cylinder test](./assays/cylinder.md) | Left, right and both-paw wall contacts, contralateral use, asymmetry index |
| [Gait analysis](./assays/gait.md) | Stride, stance, swing, duty factor, base of support, interlimb phase, gait pattern, speed-matched values |
| [Itch (scratching)](./assays/itch.md) | Scratching bouts, time, latency and trains after a pruritogen, which hind paw, time course |
| [Spontaneous pain](./assays/pain.md) | Licking/biting and flinching of the injected paw, formalin phase I / II, time course |
| [Self-grooming](./assays/grooming.md) | Grooming time, bouts, latency, body regions, interrupted bouts and incorrect transitions |
| [Seizure scoring](./assays/seizure.md) | Myoclonic jerks, clonic and tonic-clonic seizures, latencies, estimated Racine stage |

## Who it is for

Laboratories that film mice in standard behavioral tests and want keypoint-level measures without writing code or sending videos anywhere. RodentLimb gives you the numbers, the events behind them and a methods text; it does not replace checking a sample of videos by hand. See [Validation & limits](./principles/validation.md).

## Mac, iPhone and iPad

RodentLimb for Mac is built for large batches of long videos. The iPhone and iPad app uses the same analysis code and the same library format, so a library can be copied between devices and opened on either. See [iPhone & iPad](./guide/iphone.md).

## Cite

If RodentLimb contributes to published work, cite the app with its version, and the pose model's data and software. [How to cite](./models/cite.md) lists the exact references.

</div>
