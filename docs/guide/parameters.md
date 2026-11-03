# Tasks, parameters & presets

An **analysis** is one video scored for one task. A video can have several analyses, for example *Itch* and *Self-grooming* from the same recording.

## Assigning tasks

- At import, tick the **planned tasks**: their analyses are created as soon as each video is included.
- Later, select videos in a table and choose **Assign Tasks…**.
- Analyses are computed in the background, several at a time.

## Changing parameters

Open an analysis; its parameters are in the inspector on the right. The result is recomputed immediately, because the model never runs again: only the cleaning and the scoring are repeated.

**Apply to…** copies the parameters to the other analyses of the same task in the study (or the selection). Each video keeps its own **injection time** and **injected paw**, which differ from video to video. Use the same parameters for every animal of a study, and report them: every value goes into the methods export.

## Keypoint cleaning (all tasks)

| Parameter | Default | Effect |
|---|---|---|
| Keypoint confidence | 0.30 | Points below it are treated as missing |
| Fill gaps up to | 0.25 s | Shorter gaps are filled; longer ones stay missing and are excluded from every measure |
| Fill method | Linear | Also: shape-preserving cubic, body-relative (the paw moves with the body), Kalman smoother |
| Remove implausible jumps | Off | Treats a point far from where its neighbouring frames put it as missing |
| Jump threshold | 0.5 BL | Distance from the ±0.1 s median position |
| Position smoothing | 0.10 s (gait 0.03 s) | Centred moving average after a 3-point median filter |

Details: [Pose estimation & cleaning](../principles/pose.md).

## Presets from published protocols

At the top of the inspector, **Protocol** offers presets that set the values that a published protocol defines: scoring window, phases, bins, bout rules, stride filters or keypoint confidence. It leaves the camera view, the lesioned side, the injection time, the injected paw and the calibration as they are. The defaults are those of the iPhone app, so existing results do not change unless you choose a preset.

| Task | Preset | Key settings | Source |
|---|---|---|---|
| Tail suspension | **Last 4 of 6 min** (default) | Scored 2:00–6:00 | Can et al., 2012 |
| | Whole 6 min | 0:00–6:00 | Steru et al., 1985 |
| Spontaneous pain | **Formalin 0–10 / 10–60 min** (default) | 5-min bins | Mogil et al., 1999 |
| | Formalin 0–5 / 20–30 min | The two licking peaks in mice | Hunskaar et al., 1985; Hunskaar & Hole, 1987 |
| | Formalin 0–5 / 20–40 min | Mouse protocol | Nian et al., 2014 |
| Gait | **App default** | ≥ 1 BL/s, turning ≤ 30 °/s, first and last stride of a run dropped | RodentLimb simulations |
| | Open-field strides (JAX) | About 0.5 BL/s (tail base ≥ 5 cm/s), ±20 °/s, confidence > 0.3 | Sheppard et al., 2022 |
| Cylinder | First 20 contacts | Scoring stops at 20 contacts | Schallert et al., 2000 |
| | 5-minute session | All contacts in the first 5 min | Bentea et al., 2025 (protocols.io) |
| | **Whole video** (default) | No limit | |
| Itch | **Acute pruritogen: 30 min** (default) | 5-min bins; bouts < 2 s apart form a train | Park et al., 2019; Kobayashi et al., 2021; Yu et al., 2022 |
| | Spontaneous / chronic itch: 60 min | 10-min bins | Common practice in chronic itch models |
| Self-grooming | **10-minute session** (default) | A pause > 5 s ends a bout | Estanislau, 2012 |
| | Kalueff: 5 min, 6-s bouts | Pauses < 6 s are interruptions within a bout | Kalueff & Tuohimaa, 2004; Kalueff et al., 2007 |
| | After 10-min habituation (10–20 min) | Autism-model protocol | McFarlane et al., 2008; Silverman et al., 2010 |
| Seizure | **PTZ: 30 min** (default) | Revised Racine scale (stages 1–7) | Van Erum et al., 2019 |
| | Kainate / pilocarpine: 2 h | Modified Racine scale (1–5), 10-min bins | Racine, 1972; Sharma et al., 2018 |
| All tasks | Keypoints: confidence 0.6 + remove jumps | Stricter, more gaps | DeepLabCut's default cut-off (Mathis et al., 2018) |

**How we chose the defaults.** Time windows, phases and bins are part of the experimental design, so the presets use the published values, which also makes results comparable with published data. Speed and distance thresholds in body lengths depend on the camera and the animal's size; published values in cm/s can only be converted approximately, so the app's defaults stay as they are and the published settings are offered as presets. A confidence of 0.6 removes more wrong positions but leaves more gaps; for short videos or frequent occlusion, 0.3 is usually better. Use one preset for every animal of a study.

The parameters specific to each task are on its page under [Tasks](../assays/).
