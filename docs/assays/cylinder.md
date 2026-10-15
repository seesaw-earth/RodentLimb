# Cylinder test

The cylinder test (Schallert et al., 2000) measures **forelimb use asymmetry**. A mouse placed in a transparent cylinder rears and touches the wall with its forepaws. After a unilateral lesion (stroke, 6-OHDA, cortical injury), the paw contralateral to the lesion is used less.

## Recording and calibration

Bottom view through the clear floor works best; a side view also works. Mark the **rim circle** (bottom view) or the **floor line** (side view) in [Calibration](../guide/calibration.md). Without calibration no contacts can be found, and the result asks you to calibrate.

## How a wall contact is detected

A forepaw is **on the wall** in a frame when both of these hold:

- it is **still**: speed below the *still paw speed* (0.8 BL/s);
- it is **at the wall**:
  - bottom view: within the *wall zone* of the rim (outer 15 % of the radius);
  - side view: raised above the floor line by at least the *paw height* (0.30 BL).

Dropouts of one or two frames are bridged. A run of such frames lasting at least the *minimum contact* (0.10 s) is one **placement**.

## From placements to scores

- **Rears**: placements less than the *rear gap* (0.5 s) apart belong to the same rear.
- **First contact per rear** (default, Schallert et al., 2000): in each rear, the first paw placed is scored *left* or *right*. If the other paw follows within the *simultaneous window* (0.2 s), the rear is scored *both*.
- **Every contact**: each placement is scored. Left and right placements starting within the simultaneous window are merged into *both*.
- **Limits**: you can score only the first N seconds or the first N contacts (some protocols use the first 20 contacts or 3–5 minutes).

## Checking and correcting

Open **Review**. Each contact is listed with its time. Tap to play it, and change its label to *Left, Right, Both* or *Ignore* if the automatic call is wrong. Edits are stored by frame, kept when parameters change, counted in *Manually edited events*, and exported in `…_contacts.csv` (auto and final label).

## Measures

| Measure | Definition |
|---|---|
| Wall contacts scored | Left + right + both (after edits and limits) |
| Left / right / both paws | Counts |
| Left / right / both (% of all) | Count ÷ total × 100 |
| **Contralateral use** | contra ÷ (ipsi + contra) × 100 (Magno et al., 2019) |
| Contralateral incl. ½ both | (contra + ½ both) ÷ total × 100 |
| **Asymmetry index** | (ipsi − contra) ÷ (ipsi + contra + both) × 100 |
| Ipsilateral / contralateral | Counts relative to the lesioned hemisphere |
| Left use, L/(L+R) · Left − right bias | Shown when no lesion side is set |
| Rears with wall contact | Number of rears |
| Paw on wall (s), mean placement (s) | Per paw |
| Time to 20 contacts | Onset time of the 20th scored contact |
| Forepaw visibility | Detection rate of the less visible forepaw (% of frames) |

Set the **lesioned hemisphere** in Parameters to get the lesion-relative measures. A left-hemisphere lesion makes the right paw contralateral.

## Parameters

| Parameter | Default | Effect |
|---|---|---|
| Camera | Bottom view | Bottom (rim circle) or side (floor line) |
| Lesioned hemisphere | Not set | Enables ipsi/contra measures |
| Scoring | First contact per rear | Or every contact |
| Swap left/right labels | Off | Use when the model's L/R refers to image sides (mirrored view) |
| Wall zone | 0.15 × r | Bottom view |
| Paw height | 0.30 BL | Side view |
| Still paw speed | 0.8 BL/s | Raise if contacts are missed; lower if passing paws are counted |
| Minimum contact | 0.10 s | Shortest placement |
| Simultaneous window | 0.20 s | Left + right within this = both |
| Rear gap | 0.5 s | Placements closer than this form one rear |
| Score first / contact limit | none | Time or count limit |
