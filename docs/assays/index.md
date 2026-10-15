# Assays

<div class="rf-cards">
  <a class="tst" href="./tail-suspension.html"><strong>Tail suspension</strong><span>Immobility, latency, bouts, per-minute profile, tail climbing and an estimated clasping score.</span></a>
  <a class="cyl" href="./cylinder.html"><strong>Cylinder test</strong><span>Forelimb wall contacts during rearing: left, right, both, and lesion-relative asymmetry.</span></a>
  <a class="gait" href="./gait.html"><strong>Gait analysis</strong><span>Stance, swing, stride, duty factor, base of support, interlimb phase, gait pattern and sway.</span></a>
</div>

## Common to all assays

- One mouse per video. The pose model finds seven keypoints in every frame ([Pose model & cleaning](../principles/pose.md)).
- Positions are cleaned (confidence filter, gap filling, smoothing) before any measure is computed.
- Distances and speeds are in **body lengths (BL)**, the median nose–tail-base distance, unless a cm scale is calibrated (gait).
- Each result lists **pose coverage**. When it is low, a note says so, and the measures should be read with care.
- Every parameter can be changed after detection; see [Parameters](../guide/parameters.md).

| | Tail suspension | Cylinder | Gait |
|---|---|---|---|
| Camera | Front / back of the hanging mouse | Below (or side) | Below a walkway |
| Calibration | — | Rim circle or floor line | Optional cm ruler |
| Key measures | Immobility s / % | Contralateral use, asymmetry | Stride, duty factor, base of support |
| Manual review | Motion chart, video | Every contact can be relabeled | Footfall pattern, video |
