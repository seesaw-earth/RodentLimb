# Itch (scratching)

Mice scratch an itchy spot with a hind paw in rapid series of strokes. After an injected pruritogen, observers count the scratching bouts and the time spent scratching, usually over 30–60 minutes in 5-minute bins (Kuraishi et al., 1995). RodentLimb finds these bouts from the hind paws' fast back-and-forth movement near the head.

## Recording

From below through a clear floor, one mouse per chamber, **≥ 30 fps** (60 fps is better: strokes are fast). Record 30–60 min from the injection. If the video starts earlier, set the **injection time** in the parameters; latency, window and bins are measured from it. See [Recording videos](../guide/recording.md#per-task).

## How scratching is detected

A frame is scored as scratching when, together:

1. **A hind paw moves back and forth fast.** Its *high-frequency energy* — the squared distance from its own 0.2-s rolling median, averaged over 0.5 s, in body lengths² — exceeds both the *energy threshold* (10^−2.6 BL²) and 2.5 × this video's own keypoint jitter on still paws, so that tracking noise is not counted.
2. **The paw is near the head**: within the *head distance* (0.65 BL).
3. **The body stays in place**: slower than the *maximum body speed* (1.5 BL/s).

Scratching frames less than the *merge gap* (0.5 s) apart form one **bout**, following the definition that a bout ends when the hind paw returns to the floor or pauses (Kuraishi et al., 1995). Bouts shorter than the *minimum bout* (0.3 s) are dropped. The scratching paw (left or right) is the one with more high-frequency movement during the bout.

Bouts less than the *train gap* (2 s) apart are grouped into **trains**, because scratching and paw licking alternate within one episode (Yu et al., 2022).

If a trained scratching classifier (`ScratchModel.json`, trained on the Scratch-AID dataset of Yu et al., 2022) is added to the app, it is used instead of the rules; the methods text then says so. The app as distributed uses the keypoint rules.

## Cheek model: itch vs pain

Injected into the cheek, a pruritogen evokes hind-paw scratching and an algogen evokes forepaw wiping (Shimada & LaMotte, 2008). With *Injection site: Cheek*, RodentLimb also scores **unilateral forepaw wiping** as pain-like behavior: one forepaw at the face (within 0.22 BL of the head) stroking, the other forepaw at least 0.12 BL farther away, head facing forward, body in place. Bilateral strokes are grooming and are not counted (Yamanoi et al., 2019).

## Review

Every bout is listed in **Review**. Relabel a bout as *Scratching bout*, *Forepaw wiping (pain-like)* or *Not this behavior (ignore)*; the measures update.

## Measures

| Measure | Definition |
|---|---|
| Scratching bouts | Number of bouts in the window |
| Scratching time | Total bout duration (s) |
| Latency to first bout | From the injection (s) |
| Scratching (% of window) | Scratching time ÷ window × 100 |
| Bouts per minute | Bouts ÷ window length |
| Mean bout duration · Longest bout | s |
| Scratching trains · Mean train duration | Bouts < 2 s apart grouped |
| Bouts with the left / right hind paw · Side index | (L − R) ÷ (L + R) × 100 |
| Forepaw wiping bouts · Wiping time · Wipes with the left / right forepaw | Cheek model only |
| Manually edited events · Pose coverage | Quality |

Charts: scratching per time bin from the injection; the event timeline.

## Parameters

| Parameter | Default |
|---|---|
| Injection time | 0 s (start of the video) |
| Window | 0–30 min after the injection |
| Time bin | 5 min |
| Injection site | Nape / back (or cheek) |
| Energy threshold | 10^−2.6 BL² (0.5-s mean) |
| Head distance | 0.65 BL |
| Maximum body speed | 1.5 BL/s |
| Merge gap · Minimum bout | 0.5 s · 0.3 s |
| Train gap | 2 s |

## Presets

| Preset | Settings | Source |
|---|---|---|
| **Acute pruritogen: 30 min** (default) | 5-min bins | Park et al., 2019; Kobayashi et al., 2021; Yu et al., 2022 |
| Spontaneous / chronic itch: 60 min | 10-min bins | Common practice in chronic itch models (e.g. MC903, AEW) |

## Limits

- Scratching strokes are fast; at 30 fps some short bouts may be missed. Use 60 fps if you can.
- Scratching of the body flank (not the head or neck) can fall outside the head distance.
- Grooming of the face with the hind paws is rare in mice but would look similar; review a sample.

## References

- Kuraishi Y., Nagasawa T., Hayashi K., Satoh M. (1995) Scratching behavior induced by pruritogenic but not algesiogenic agents in mice. *Eur J Pharmacol* 275:229–233.
- Shimada S.G., LaMotte R.H. (2008) Behavioral differentiation between itch and pain in mouse. *Pain* 139:681–687.
- Akiyama T., Carstens M.I., Carstens E. (2010) Differential itch- and pain-related behavioral responses and µ-opioid modulation in mice. *Acta Derm Venereol* 90:575–581.
- Yamanoi Y., Kittaka H., Tominaga M. (2019) Cheek injection model for simultaneous measurement of pain and itch-related behaviors. *J Vis Exp* 151:e58943.
- Yu H. et al. (2022) Scratch-AID, a deep learning-based system for automatic detection of mouse scratching behavior with high accuracy. *eLife* 11:e84042.
- Elliott P. et al. (2017) Automated acoustic detection of mouse scratching. *PLoS ONE* 12:e0179662.
