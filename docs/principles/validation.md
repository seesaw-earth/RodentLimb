# Validation

## What has been checked

The three analyzers were ported line-for-line to Python and run on **simulated mice with known ground truth** (the scripts are in `Tools/validation/` in the repository).

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

## What simulation cannot tell you

Simulations test the **analysis**, not the **pose model** on your videos. Before using the results in a study:

1. **Check the overlay** on a few videos in the Review tab.
2. **Score a subset by hand**, blinded, for example 10 % of animals, and compare: immobility time, contact counts, stride measures.
3. **Fix the parameters** that best match your manual scoring, apply them to all sessions, and report them (the methods export contains them).
4. For cylinder sessions, **review the contact list**. Corrections are stored and counted.

Report the agreement (for example a correlation or Bland–Altman plot) in your methods.
