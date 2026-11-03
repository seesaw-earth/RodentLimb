# Spontaneous pain

After an injection into a paw (formalin, capsaicin, CFA and others), mice lick and bite the paw and flinch it. In the formalin test these behaviors come in an early **phase I** (direct activation of nociceptors) and a late **phase II** (inflammation and central sensitization) (Dubuisson & Dennis, 1977; Hunskaar & Hole, 1987). RodentLimb measures licking/biting and flinching of the injected paw from the bottom view.

## Recording

From below through a clear floor so the injected paw is visible, **≥ 30 fps**, in normal light. Formalin: record 45–60 min from the injection; capsaicin: 5–10 min. Set the **injected paw** and the **injection time** in the parameters. See [Recording videos](../guide/recording.md#per-task).

## How behaviors are detected

**Licking / biting.** The mouth (or the nose when the mouth is not tracked, as with the near-infrared model) is within the *lick distance* (0.30 BL) of the injected paw while the body moves slower than 1.5 BL/s. When both paws are that close, the nearer one is credited. Episodes less than 1.0 s apart are joined; episodes shorter than 0.5 s are dropped. Any contact of the mouth with the injected paw is counted (Wotton et al., 2020). Licking of the other paw is measured the same way, as a within-animal control (grooming also involves paw licking).

**Flinch / shake.** A brief (≤ 0.30 s) movement of the injected paw faster than the *flinch speed* (4.0 BL/s, measured over about 33 ms; raised to 4 × the paw's median speed at rest when the track is noisy), while:

- the body moves slower than 1.0 BL/s for ±0.3 s,
- the other paw is not moving equally fast at the same moment (that would be a left/right label swap), and
- no licking occurs within 0.5 s (the paw is not being lifted to or from the mouth).

Guarding and weight bearing need paw contact area or pressure, which keypoints do not give; they are not scored.

## Phases

Phase I = 0–10 min and phase II = 10–60 min after the injection by default (Mogil et al., 1999), with 5-min bins. Other published phase definitions are available as presets.

## Review

Every event is listed in **Review**. Relabel it as *Licking / biting injected paw*, *Flinch / shake*, *Licking the other paw* or *Not this behavior (ignore)*.

## Measures

| Measure | Definition |
|---|---|
| Licking, phase I · phase II · interphase · whole window | Licking/biting time of the injected paw (s) |
| Licking bouts · Latency to first licking · Mean licking bout | |
| Flinches · Flinches, phase I · phase II | Counts |
| Licking the other paw | s |
| Injected paw share of paw licking | Injected ÷ (injected + other) × 100 |
| Injected paw visibility | % of frames in which the injected paw was tracked |
| Manually edited events · Pose coverage | Quality |

Charts: licking time and flinches per time bin; the event timeline.

## Parameters

| Parameter | Default |
|---|---|
| Injection time | 0 s |
| Injected paw | Right hind paw |
| Phase I end · Phase II | 10 min · 10–60 min |
| Time bin | 5 min |
| Lick distance | 0.30 BL |
| Maximum body speed (licking) | 1.5 BL/s |
| Minimum licking · Merge gap | 0.5 s · 1.0 s |
| Flinch speed · Maximum flinch duration | 4.0 BL/s · 0.30 s |
| Body still for flinches | < 1.0 BL/s |

## Presets

| Preset | Phases | Source |
|---|---|---|
| **Formalin 0–10 / 10–60 min** (default) | 5-min bins | Mogil et al., 1999 |
| Formalin 0–5 / 20–30 min | The two licking peaks in mice | Hunskaar et al., 1985; Hunskaar & Hole, 1987 |
| Formalin 0–5 / 20–40 min | Mouse protocol | Nian et al., 2014 |

## Limits

- Flinching is fast; at 30 fps short flinches can be missed or merged.
- The injected paw must be visible from below; a paw tucked under the body is not tracked.
- With the near-infrared model there is no mouth keypoint; the snout is used.

## References

- Dubuisson D., Dennis S.G. (1977) The formalin test: a quantitative study of the analgesic effects of morphine, meperidine, and brain stem stimulation in rats and cats. *Pain* 4:161–174.
- Hunskaar S., Hole K. (1987) The formalin test in mice: dissociation between inflammatory and non-inflammatory pain. *Pain* 30:103–114.
- Tjølsen A., Berge O.G., Hunskaar S., Rosland J.H., Hole K. (1992) The formalin test: an evaluation of the method. *Pain* 51:5–17.
- Mogil J.S. et al. (1999) Heritability of nociception I: responses of 11 inbred mouse strains on 12 measures of nociception. *Pain* 80:67–82.
- Wotton J.M. et al. (2020) Machine learning-based automated phenotyping of inflammatory nocifensive behavior in mice. *Mol Pain* 16:1744806920958596.
