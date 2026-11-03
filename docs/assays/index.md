# Tasks

RodentLimb scores seven tasks from the same keypoints. A video is tracked once; you can then run several tasks on it, and change any parameter afterwards.

<div class="rf-cards">
  <a class="tst" href="./tail-suspension.html"><strong>Tail suspension</strong><span>Immobility, latency, bouts, per-minute profile, tail climbing and an estimated clasping score.</span></a>
  <a class="cyl" href="./cylinder.html"><strong>Cylinder test</strong><span>Forelimb wall contacts during rearing: left, right, both, and lesion-relative asymmetry.</span></a>
  <a class="gait" href="./gait.html"><strong>Gait analysis</strong><span>Stance, swing, stride, duty factor, base of support, interlimb phase, gait pattern and sway.</span></a>
  <a class="itch" href="./itch.html"><strong>Itch</strong><span>Hind-paw scratching bouts, time, latency and trains; forepaw wiping in the cheek model.</span></a>
  <a class="pain" href="./pain.html"><strong>Spontaneous pain</strong><span>Licking / biting and flinching of the injected paw, by formalin phase.</span></a>
  <a class="groom" href="./grooming.html"><strong>Self-grooming</strong><span>Grooming time and bouts by body region, interrupted bouts and head-to-tail transitions.</span></a>
  <a class="sz" href="./seizure.html"><strong>Seizure scoring</strong><span>Candidate seizure events on a Racine-type scale, estimated stage and latencies, for review.</span></a>
</div>

## Common to all tasks

- One mouse per video. The pose model finds seven keypoints in every frame ([Pose estimation & cleaning](../principles/pose.md)).
- Positions are cleaned (confidence filter, gap filling, smoothing) before any measure is computed.
- Distances and speeds are in **body lengths (BL)**, the median nose–tail-base distance, unless a cm scale is calibrated (gait).
- Each result lists **pose coverage**. When it is low, a note says so, and the measures should be read with care.
- Every parameter can be changed after detection, and **protocol presets** set the published time windows; see [Parameters](../guide/parameters.md).
- Every detected event can be reviewed on the video and relabeled; the number of edits is reported.
- The **methods text** in the export describes the scoring with your parameter values and the references.

## Motor tests

| | Tail suspension | Cylinder | Gait |
|---|---|---|---|
| Camera | Front / back of the hanging mouse | Below (or side) | Below a walkway |
| Calibration | — | Rim circle or floor line | Optional cm ruler |
| Key measures | Immobility s / % | Contralateral use, asymmetry | Stride, duty factor, base of support |
| Review | Motion chart, video | Every contact can be relabeled | Footfall pattern, video |

## Behavior after an injection

| | Itch | Spontaneous pain | Self-grooming | Seizure |
|---|---|---|---|---|
| Camera | Below, clear floor | Below, injected paw visible | Below | Below |
| Time zero | Injection time | Injection time | Start of the video | Injection time |
| Key measures | Scratching bouts, time, latency | Licking time per phase, flinches | Grooming time, bouts, microstructure | Maximal stage, latencies |
| Default window | 30 min in 5-min bins | Phase I 0–10, phase II 10–60 min | 0–10 min in 1-min bins | 30 min in 1-min bins |
| Review | Every bout | Every licking episode and flinch | Every bout | Every event, confirm the stage |

::: warning First pass, then review
The thresholds of the four behavior tasks were set on simulated data and have not yet been validated against manual scoring of real videos. Review the events, and compare with blinded manual scoring on a subset of your videos before you report results. See [Validation](../principles/validation.md).
:::
