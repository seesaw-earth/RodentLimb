# Seizure scoring

Behavioral seizures after a convulsant are scored on a Racine-type scale (Racine, 1972). RodentLimb finds candidate seizure events from the bottom view, estimates the stage reached and reports the latencies. **Every event is a first pass that a reviewer confirms on the video.**

## Recording

From below through a clear floor or cylinder, one mouse, **≥ 30 fps**, in normal light. Start before the convulsant injection and record at least 30 min after it; set the **injection time** in the parameters. See [Recording videos](../guide/recording.md#per-task).

## Scales

**PTZ in mice — revised Racine scale** (Van Erum et al., 2019, extending Lüttjohann et al., 2009):
0 whisker trembling · 1 sudden behavioral arrest, motionless staring · 2 facial jerking · 3 neck jerks · 4 clonic seizure in a sitting position · 5 clonic or tonic-clonic seizure lying on the belly · 6 lying on the side and/or wild jumping · 7 tonic extension. Stages 0–2 are focal, 3–6 generalized.

**Kainate / pilocarpine — modified Racine scale** (Racine, 1972; Sharma et al., 2018):
1 immobility · 2 facial automatisms · 3 forelimb clonus · 4 rearing and falling · 5 generalized tonic-clonic seizure with lateral recumbency, jumping or wild running.

Whisker trembling and facial jerks cannot be seen from below and are not scored.

## Candidate events

| Event | Stage (PTZ / kainate scale) | Rule |
|---|---|---|
| **Myoclonic jerk** | 3 / 2 | A whole-body twitch: the median keypoint speed (over about 33 ms) exceeds 4.0 BL/s, with at least 4 body parts faster than half that speed, for ≤ 0.5 s, starting from a quiet animal (< 1.0 BL/s over the previous 0.5 s); the body stays within 0.4 BL over the next 0.5 s |
| **Clonic seizure, upright** | 4 / 3 | Rhythmic fast movement of at least 3 body parts, including a forepaw and a hind paw, above max(10^−2.4 BL², 5 × jitter), body in place, for ≥ 3 s (the NINDS subcutaneous PTZ end point: clonus for about 3–5 s) |
| **Convulsions on the belly / falling** | 5 / 4 | Not detected separately: relabel a clonic seizure when the mouse is prone |
| **Convulsions on the side** | 6 / 5 | All paws on one side of the body axis (the flank faces the camera) for ≥ 1 s |
| **Wild running / jumping** | 6 / 5 | Body speed > 8.0 BL/s for ≥ 0.3 s, or the animal reappearing > 1.5 BL away within 1 s |
| **Tonic hindlimb extension** | 7 / 5 | Both hind paws stretched behind the tail base and rigid (< 1 BL/s) for ≥ 1 s |
| **Behavioral arrest** (off by default) | 1 / 1 | Movement < 0.15 BL/s for ≥ 5 s right after movement, before the first generalized seizure. From below, an arrest looks like an ordinary pause, so it is only meaningful when the baseline is active |

Overlapping detections take the higher stage; generalized events less than 5 s apart form one **episode** (Van Erum et al., 2019 merged EEG events < 5 s apart). Detections **before the injection** are listed but not counted; their number is a built-in false-positive check.

## Review

Every event is listed in **Review** with its stage. Confirm or relabel it on the video, or mark it *Not this behavior (ignore)*; the stage, latencies and counts update.

## Measures

| Measure | Definition |
|---|---|
| Maximal stage (est.) · Time to maximal stage | |
| Latency to first myoclonic jerk | From the injection (s) |
| Latency to first generalized seizure | Stage ≥ 3 (PTZ scale) |
| Latency to convulsions on the side / jumping · to tonic hindlimb extension | s |
| Myoclonic jerks · Clonic seizures, upright · Convulsions with loss of posture, jumping or tonic extension | Counts |
| Time in generalized seizures · Seizure episodes · Longest episode | |
| Behavioral arrests | When scored |
| Suspected death | No movement after tonic extension |
| Detections before injection | False-positive check |
| Manually edited events · Pose coverage | Quality |

## Parameters

| Parameter | Default |
|---|---|
| Injection time | 0 s |
| Scale | PTZ, mouse (Van Erum 2019, 1–7) |
| Observation after injection · Time bin | 30 min · 1 min |
| Jerk speed · maximum duration · quiet speed | 4.0 BL/s · 0.5 s · 1.0 BL/s |
| Clonus energy · minimum duration | 10^−2.4 BL² · 3.0 s |
| Loss of posture, minimum | 1.0 s |
| Running speed · minimum duration | 8.0 BL/s · 0.3 s |
| Tonic extension, minimum | 1.0 s |
| Score behavioral arrest | Off (5 s, < 0.15 BL/s when on) |
| Episode gap | 5 s |

## Presets

| Preset | Settings | Source |
|---|---|---|
| **PTZ: 30 min** (default) | Revised Racine scale (1–7) | Van Erum et al., 2019 |
| Kainate / pilocarpine: 2 h | Modified Racine scale (1–5), 10-min bins | Racine, 1972; Sharma et al., 2018 |

::: warning Automated stages are estimates
Seizure stages are defined by observers watching the animal, often with EEG. The automated stage is a starting point for review, not a replacement. Report how many events were confirmed or relabeled (the methods text counts the edits).
:::

## References

- Racine R.J. (1972) Modification of seizure activity by electrical stimulation. II. Motor seizure. *Electroencephalogr Clin Neurophysiol* 32:281–294.
- Lüttjohann A., Fabene P.F., van Luijtelaar G. (2009) A revised Racine's scale for PTZ-induced seizures in rats. *Physiol Behav* 98:579–586.
- Van Erum J., Van Dam D., De Deyn P.P. (2019) PTZ-induced seizures in mice require a revised Racine scale. *Epilepsy Behav* 95:51–55.
- Ferraro T.N. et al. (1999) Mapping loci for pentylenetetrazol-induced seizure susceptibility in mice. *J Neurosci* 19:6733–6739.
- Sharma S., Puttachary S., Thippeswamy A., Kanthasamy A.G., Thippeswamy T. (2018) Status epilepticus: behavioral and electroencephalography seizure correlates in kainate experimental models. *Front Neurol* 9:7.
- Copping N.A., Silverman J.L. (2021) Abnormal electrophysiological phenotypes and sleep deficits in a mouse model of Angelman syndrome. *Mol Autism* 12. https://doi.org/10.1186/s13229-021-00416-y
