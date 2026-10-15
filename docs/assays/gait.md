# Gait analysis

RodentLimb measures each paw's **stance** (on the ground) and **swing** (in the air) from a bottom view of a walking mouse, then derives spatial, temporal and coordination measures. The methods follow LocoMouse (Machado et al., 2015), CatWalk-style measures (Hamers et al., 2001), and the stride-level approach of Sheppard et al. (2022), including its handling of walking speed.

## Recording

Bottom view of a straight walkway, **≥ 60 fps**. Put a ruler in view once if you want cm. See [Recording](../guide/recording.md#gait-analysis).

## Stance and swing

A paw is in stance while it is stationary on the floor. For every frame, the app takes the **smaller of the backward and forward steps** of the paw. That keeps the touch-down and lift-off frames in stance, which a central difference would miss. The paw is in stance when this speed is below:

> max( *stance floor* × BL/s , *stance ratio* × body speed )

Body speed is the speed of the midpoint between nose and tail base. Phases shorter than the *minimum phase* (30 ms) are merged into their neighbors. Each stance has a **footprint**: the mean paw position during that stance.

<figure>

![Stance, swing, stride and phase](/img/stride.en.svg)

<figcaption>Footfall pattern of a trotting mouse. A stride runs from one foot strike to the next of the same paw; the phase of another paw is when it strikes within that stride.</figcaption>
</figure>

## Which strides count

A stride is kept only if:

- it lasts at most the *maximum stride* (1 s);
- the body moves at least the *minimum walking speed* (1.0 BL/s);
- the mouse walks **straight**: mean |angular velocity| ≤ the *maximum turning rate* (30 °/s; Sheppard et al. used ±20 °/s);
- it is **not the first or last stride of a continuous run**, where the mouse accelerates or slows down (can be switched off).

*Strides excluded for turning* tells you how many were rejected for turning.

## Measures

### Speed

| Measure | Definition |
|---|---|
| Walking speed | Mean body speed over the analyzed strides (cm/s or BL/s) |
| Speed variability (CV) | SD ÷ mean of stride speed |
| Strides analyzed · Time walking | Counts and % of frames above the minimum speed |

### Spatial

| Measure | Definition |
|---|---|
| Stride length (fore, hind; hind in BL) | Distance between consecutive footprints of the same paw |
| Step length, hind | Distance from a left hind print to the next right hind print, along the walking direction |
| Base of support (fore, hind) | Lateral distance between left and right footprints, perpendicular to the walking direction (step width) |
| Print position (left, right) | Distance between a hind print and the preceding fore print on the same side |

### Temporal

| Measure | Definition |
|---|---|
| Stride frequency | 1 ÷ mean hind stride duration |
| Stance, swing (fore, hind) | Durations |
| Duty factor (fore, hind) | Stance ÷ stride duration × 100 |

### Speed-matched values

Almost every gait measure changes with speed (Batka et al., 2014), so comparing raw means between groups that walked at different speeds can be misleading. For each animal, RodentLimb fits a straight line of the measure against stride speed and reads it at the **reference speed** (default 2.0 BL/s):

- hind stride length (BL), stride frequency, hind duty factor and hind swing **@ reference speed**.

At least 8 hind strides with some spread in speed are needed. If the animal never walked near the reference speed (outside 0.75×–1.25× of its observed range), the value is left blank rather than extrapolated. Use the same reference speed for the whole study. Per-stride speed is in the strides export if you prefer a mixed model with speed as a covariate (Sheppard et al., 2022).

### Variability and symmetry

| Measure | Definition |
|---|---|
| Stride length / time variability (CV) | SD ÷ mean over hind strides; increases in ataxia (Machado et al., 2015) |
| Hind stride L−R asymmetry | (L − R) ÷ mean(L, R) × 100 for stride length |

### Coordination

| Measure | Definition |
|---|---|
| Interlimb phase | (strike of target − strike of reference) ÷ reference stride, for LH→RH, LF→RF, LH→LF and LH→RF. Circular mean, 0–1 |
| Hind coupling strength (R) | Resultant length of LH→RH phases: 1 = perfectly consistent, 0 = random |
| Regularity index | 4 × normal step-sequence patterns ÷ paw placements × 100 (Cheng et al., 1997) |
| Gait pattern (% walk, trot, gallop, bound) | Per hind stride, after Bellardita & Kiehn (2015): hind phase 0.5 ± 0.15 → *walk*, or *trot* if the diagonal (LH→RF) phase is 0 ± 0.15; hind phase 0 ± 0.15 → *bound*; otherwise *gallop* |

A phase of **0.5** means the two paws alternate; **0 or 1** means they move together.

### Whole-body posture

| Measure | Definition |
|---|---|
| Nose / tail-base lateral sway | Within each stride, the side-to-side range of the point relative to the line joining the body center at the stride's start and end, in BL (Sheppard et al., 2022) |
| Nose / tail-base sway phase | Where in the stride the point is furthest to one side (circular mean, 0–1) |

## Charts

- **Footfall pattern** (Summary and Review): stance bars for LF, RF, LH, RH. In Review it follows the video.
- **Gait pattern**: share of walk, trot, gallop and bound strides.
- **Per paw** table, **interlimb coordination** dials and the **footprint** map (Measures).

## Parameters

| Parameter | Default | Effect |
|---|---|---|
| Stance speed ratio | 0.8 × body speed | Least biased value on simulated walking at 30–100 fps |
| Stance speed floor | 0.8 BL/s | Minimum threshold when the body is slow |
| Minimum phase | 0.03 s | Shorter stance/swing flickers are merged |
| Swap left/right labels | Off | For mirrored views |
| Minimum walking speed | 1.0 BL/s | Strides slower than this are ignored |
| Maximum turning rate | 30 °/s | Strides while turning faster are ignored |
| Drop first and last stride of each run | On | Removes acceleration and deceleration |
| Maximum stride | 1.0 s | Longer intervals are pauses, not strides |
| Reference speed | 2.0 BL/s | For speed-matched values |
| Position smoothing | 0.03 s | Lighter than other assays, because swings last only about 0.1 s |
