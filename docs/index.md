---
layout: home
title: RodentLimb
titleTemplate: User manual

hero:
  name: RodentLimb
  text: Limb pose for motor and behavior tests, on iPhone
  tagline: Track four paws, nose and tail base in every frame, then score tail suspension, cylinder and gait tests. It all runs on the phone, and nothing is uploaded.
  image:
    src: /hero.png
    alt: RodentLimb app icon
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Assays
      link: /assays/
    - theme: alt
      text: Source on GitHub
      link: https://github.com/seesaw-earth/RodentLimb
    - theme: alt
      text: 中文版
      link: /zh/

features:
  - title: Seven keypoints, every frame
    details: A pose model trained on mouse videos finds the four paws, tail base, nose and mouth in every video frame, on the iPhone itself.
    link: /principles/pose
    linkText: Pose model
  - title: Tail suspension
    details: Immobility time and %, latency, bouts, per-minute profile, tail climbing, and an estimated hindlimb clasping score.
    link: /assays/tail-suspension
    linkText: Tail suspension
  - title: Cylinder test
    details: Left, right and both-paw wall contacts during rearing, with lesion-relative asymmetry. You can replay and relabel every contact.
    link: /assays/cylinder
    linkText: Cylinder test
  - title: Gait analysis
    details: Stance, swing, stride, duty factor, base of support, interlimb phase, gait pattern and whole-body sway. Values are also reported at a common reference speed.
    link: /assays/gait
    linkText: Gait analysis
  - title: Change a parameter, see it instantly
    details: The model runs once per video. Thresholds, windows and calibration can be changed afterwards, and results update immediately.
    link: /guide/parameters
    linkText: Parameters
  - title: Private and open source
    details: No account, no analytics, no network connection. Exports are in English with a methods paragraph you can cite. The source code is public.
    link: /source
    linkText: Source code
---

<div class="rf-home">

<p class="rf-lang">Language: <a href="./index.html">English</a> · <a href="./zh/index.html">简体中文</a></p>

## How it works

The model reads each video once and stores the keypoints. Everything after that is quick: cleaning, the assay analysis and the results are recomputed whenever you change a parameter or a label.

<figure>

![From video to results](/img/pipeline.en.svg)

</figure>

## Assays

| Assay | Main measures | Camera |
|---|---|---|
| [Tail suspension](./assays/tail-suspension.md) | Immobility (s, %), latency, bouts, clasping score, tail climbing | Front or back of the hanging mouse |
| [Cylinder test](./assays/cylinder.md) | Left / right / both wall contacts, contralateral use, asymmetry index | Below the clear floor (or side view) |
| [Gait analysis](./assays/gait.md) | Stride, stance, swing, duty factor, base of support, phase, pattern, sway | Below a clear walkway, ≥ 60 fps |

## Open source

RodentLimb is open source under the GNU AGPL-3.0. The analysis code, every metric definition and this manual are in one public repository, so you can read exactly how each number is computed.

<p class="rf-repo"><a href="https://github.com/seesaw-earth/RodentLimb">github.com/seesaw-earth/RodentLimb</a></p>

## Where to start

<div class="rf-cards">
  <a href="./guide/getting-started.html"><strong>Quick start</strong><span>From a video to your first result in a few minutes.</span></a>
  <a href="./guide/recording.html"><strong>Recording tips</strong><span>Camera position, light and frame rate for good paw tracking.</span></a>
  <a href="./assays/index.html"><strong>Assay reference</strong><span>What each assay measures and how every value is defined.</span></a>
  <a href="./principles/validation.html"><strong>Validation</strong><span>What has been checked against ground truth, and what you should check.</span></a>
</div>

</div>
