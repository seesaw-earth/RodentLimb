# Self-grooming

Mice groom in a head-to-tail sequence: paw licking, nose and face wash, head wash, body grooming, leg licking and tail/genital grooming (Kalueff et al., 2007, 2016). Besides the amount of grooming, its **microstructure** — interrupted bouts and transitions that break the head-to-tail order — is sensitive to stress (Kalueff & Tuohimaa, 2005). RodentLimb scores grooming by body region from the bottom view.

## Recording

From below through a clear floor, one mouse, **≥ 30 fps**. A 10-min session after a short habituation is common; for the splash test, start right after the spray. See [Recording videos](../guide/recording.md#per-task).

## How grooming is detected

Four regions can be told apart from below, each only while the body moves slower than 1.0 BL/s:

| Region | Rule |
|---|---|
| **Face / head** | Both forepaws (or one, the other hidden) within 0.20 BL of the mouth, and stroking: fast forepaw movement above the stroke energy (10^−3.2 BL²) and above the video's own keypoint jitter |
| **Body (flank)** | Head turned more than 50° from the trunk axis, and the head moving |
| **Hind leg / paw** | Mouth within 0.30 BL of a hind paw |
| **Tail / genitals** | Nose within 0.40 BL of the tail base (curled up) |

Hind-paw scratching near the head is excluded and reported separately. Region segments shorter than 0.5 s are dropped.

**Bouts.** A pause longer than the *bout gap* (5 s; Estanislau, 2012) ends a bout; bouts shorter than 1.0 s are dropped. A bout that contains a pause of at least 1 s is **interrupted**. A transition between regions is **correct** when it moves down the chain face → body → leg → tail; % incorrect transitions and % interrupted bouts are the microstructure measures. Thresholds for bouts and pauses vary between laboratories, so they are written into the methods export.

The four-region chain is coarser than an observer's scale; treat the microstructure as exploratory.

## Review

Every bout is listed in **Review** and can be relabeled as *Grooming bout* or *Not this behavior (ignore)*.

## Measures

| Measure | Definition |
|---|---|
| Grooming time · Grooming (% of window) | s · % |
| Grooming bouts · Latency to first grooming | n · s |
| Mean bout duration · Longest bout | s |
| Face / head · Body (flank) · Hind leg / paw · Tail / genitals | Time per region (s) |
| Face share of grooming | % |
| Interrupted bouts | % of bouts |
| Incorrect (non head-to-tail) transitions · Region transitions | % · n |
| Scratching (excluded) | s |
| Manually edited events · Pose coverage | Quality |

Charts: grooming per time bin; the ethogram of regions over time.

## Parameters

| Parameter | Default |
|---|---|
| Window · Time bin | 0–10 min · 1 min |
| Face distance | 0.20 BL |
| Leg distance | 0.30 BL |
| Tail distance | 0.40 BL |
| Head turn | 50° |
| Maximum body speed | 1.0 BL/s |
| Stroke energy | 10^−3.2 BL² |
| Minimum region segment | 0.5 s |
| Bout gap · Minimum bout | 5 s · 1.0 s |

## Presets

| Preset | Settings | Source |
|---|---|---|
| **10-minute session** (default) | A pause > 5 s ends a bout | Estanislau, 2012 |
| Kalueff: 5 min, 6-s bouts | Pauses < 6 s are interruptions within a bout | Kalueff & Tuohimaa, 2004; Kalueff et al., 2007 |
| After 10-min habituation (10–20 min) | Autism-model protocol | McFarlane et al., 2008; Silverman et al., 2010 |

## Limits

- Paw licking at the start of the chain cannot be separated from face washing from below.
- With the near-infrared model there is no mouth keypoint; the snout is used, which makes face and leg grooming less certain.

## References

- Kalueff A.V., Tuohimaa P. (2004) Grooming analysis algorithm for neurobehavioural stress research. *Brain Res Protoc* 13:151–158.
- Kalueff A.V., Tuohimaa P. (2005) Mouse grooming microstructure is a reliable anxiety marker bidirectionally sensitive to GABAergic drugs. *Eur J Pharmacol* 508:147–153.
- Kalueff A.V., Aldridge J.W., LaPorte J.L., Murphy D.L., Tuohimaa P. (2007) Analyzing grooming microstructure in neurobehavioral experiments. *Nat Protoc* 2:2538–2544.
- Kalueff A.V. et al. (2016) Neurobiology of rodent self-grooming and its value for translational neuroscience. *Nat Rev Neurosci* 17:45–59.
- Estanislau C. (2012) Cues to the usefulness of grooming behavior in the evaluation of anxiety in the elevated plus-maze. *Psychol Neurosci* 5:105–112.
- McFarlane H.G. et al. (2008) Autism-like behavioral phenotypes in BTBR T+tf/J mice. *Genes Brain Behav* 7:152–163.
- Silverman J.L., Yang M., Lord C., Crawley J.N. (2010) Behavioural phenotyping assays for mouse models of autism. *Nat Rev Neurosci* 11:490–502.
