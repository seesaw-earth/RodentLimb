# Quality control & inclusion

Every video is checked once, right after tracking and before it is scored. The check answers: was the mouse found, which keypoints were tracked, how much of what is missing can be bridged by short-gap filling, how long are the stretches that cannot, are there implausible jumps, and is the video itself suitable.

## Criteria set in advance

The criteria belong to the study and should be set before scoring, as ARRIVE 2.0 (item 3) asks: inclusion and exclusion criteria are stated in advance, and every exclusion is reported with its reason.

| Criterion | Default |
|---|---|
| Mouse (nose and tail base) usable after short-gap filling | ≥ 90 % of frames to pass; below 70 % fails |
| Longest stretch without the mouse | ≤ 10 s |
| Frame rate | ≥ 25 fps |
| Frames with implausible keypoint jumps | ≤ 2 % |

Change them on the study page, in the **Inclusion criteria (QC)** card. Videos outside a study use the defaults.

## Verdicts

- **QC passed**: every criterion is met. The video is **included automatically**.
- **QC warning**: between the pass and fail levels. Needs your decision.
- **QC failed**: below the fail level. Needs your decision; usually excluded.

## Reviewing videos

**Needs Review** in the sidebar (⌘3) lists the videos waiting for a decision.

- Watch the tracking in the QC player: it shows the raw keypoints and can jump between the stretches where the mouse was lost.
- **I** includes the video; **E** excludes it and asks for a reason; **↓ / ↑** moves to the next or previous video. **Include All Tracked** includes every tracked video in the list at once.
- Decisions are saved immediately.

Every decision and reason is written to `qc_videos.csv` in the export, together with the coverage, the longest lost stretch and the pose model. The methods text states the criteria.

## Coverage in each result

Each analysis also reports a **pose coverage** (or paw visibility) measure for the frames it uses. When it is low, a note on the result says so; read those measures with care.
