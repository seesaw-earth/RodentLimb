# Tail suspension test

The tail suspension test (Steru et al., 1985) measures how long a mouse hung by its tail stays immobile, as an index of behavioral despair used in antidepressant screening. RodentLimb also flags tail climbing and estimates hindlimb clasping (Guyenet et al., 2010).

## Recording

Film from the **front or back** so both hind paws are visible, starting at suspension. Standard duration: **6 minutes**. See [Recording](../guide/recording.md#tail-suspension).

## How immobility is scored

1. **Motion signal.** For every frame: the mean speed of the four paws and the nose, in body lengths per second. Each keypoint's speed is capped at 5 BL/s so that a single bad detection cannot dominate. At least two of the five points must be present. The tail base is left out because it sits at the suspension point. The signal is then smoothed (*motion smoothing*).
2. **Immobile frames.** Frames with motion below the **motion threshold**.
3. **Bouts.** Runs of immobile frames lasting at least the **minimum bout** count as immobility. Shorter pauses do not.
4. **Window.** Immobility is summed over the **analysis window**, by default 120–360 s (minutes 2–6), because nearly all mice struggle during the first two minutes (Can et al., 2012). If the video is shorter than the window, the whole video is used, and a note says so.

Frames without enough pose are not counted as immobile; *pose coverage* tells you how many there were.

## Tail climbing

A frame counts as climbing when the nose comes closer to the tail base than the **tail-climbing ratio** × body length. *Tail climbing %* is reported over the window. Many protocols exclude animals that climb for more than 20 % of the test, and the app notes when that happens.

## Hindlimb clasping (estimate)

During the first **clasping window** seconds (default 10 s), the app measures each hind paw's lateral distance from the body axis (tail base → nose), in body lengths:

- below the *partial clasp distance* (0.25 BL) = drawn toward the midline;
- below the *full clasp distance* (0.10 BL) = fully clasped.

Score, adapted from Guyenet et al. (2010): **0** neither paw drawn in for more than 50 % of the time; **1** one paw drawn in for more than 50 %; **2** both paws partially, for more than 50 %; **3** both paws fully, for more than 50 %.

::: warning
This is an automated approximation of a visual score. Confirm it on the video, especially for scores 1–2.
:::

## Measures

| Measure | Unit | Definition |
|---|---|---|
| Immobility time | s | Time in immobile bouts within the window |
| Immobility | % | Immobility time ÷ window length × 100 |
| Latency to first immobility | s | Start of the first qualifying bout, from video start |
| Immobility bouts | n | Bouts overlapping the window |
| Mean / longest bout | s | Duration of bouts within the window |
| Analysis window | s | Length actually analyzed |
| Tail climbing | % | Climbing frames ÷ frames with pose, in the window |
| Clasping score (est.) | 0–3 | See above |
| Left / right hind paw near midline | % | Share of the clasping window with that paw drawn in |
| Hind paw separation | BL | Mean distance between the hind paws in the window |
| Pose coverage | % | Window frames where the motion signal could be computed |

Charts: motion over time with immobile bouts shaded, and immobility per minute.

## Parameters

| Parameter | Default | Effect |
|---|---|---|
| Window start / end | 120 / 360 s | Scored part of the video |
| Motion threshold | 0.25 BL/s | Raise it if breathing or tremor is scored as mobile; lower it if passive swinging is scored as immobile |
| Minimum bout | 1.0 s | Shortest pause that counts as immobility |
| Motion smoothing | 0.25 s | Moving average of the motion signal |
| Clasping window | 10 s | From the start of the video |
| Partial / full clasp distance | 0.25 / 0.10 BL | Paw-to-midline thresholds |
| Tail-climbing ratio | 0.5 BL | Nose-to-tail-base distance that counts as climbing |

::: tip Choosing the threshold
Open a few videos, play the Review tab at 2×, and compare the *Immobile / Mobile* chip with your own judgment. Set the threshold once for the whole study, then use **Apply to all sessions**.
:::
