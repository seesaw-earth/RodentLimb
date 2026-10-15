# Calibration

Calibration tells the app where the apparatus is in the picture. It is needed for the **cylinder test**, optional for **gait**, and not used for **tail suspension**.

Open it from the session's bottom bar (**Calibrate**) or from the card that appears when a session needs it. You can calibrate while a video is still waiting in the queue.

## Working with the frame

- Move the **frame slider** to a moment where the apparatus is clearly visible.
- The keypoints of that frame are drawn to help you place the marks.
- While you drag a handle, a **loupe** magnifies the area under your finger.

## Cylinder, bottom view: the rim circle

Drag **inside** the circle to move it, and drag its **edge** to resize it. Match the inner rim of the cylinder floor. The dashed inner circle shows the **wall zone**: a still paw between the two circles counts as being on the wall.

**Auto-fit from tracking** fits the circle to where the keypoints went during the whole video. The mouse explores the whole floor, so this is usually a good start.

## Cylinder, side view: the floor line

Drag the dashed line onto the cylinder floor. **Estimate from hind paws** places it at the lowest hind-paw positions. A forepaw raised above this line by the *paw height* parameter counts as raised.

## Gait: the cm ruler

Drag both ends onto marks a known distance apart (a ruler, or the walkway width), then enter the distance. The app shows the resulting px/cm. **Remove scale** returns to body-length units.

## Reusing a calibration

- **Save for this video** saves only the current session.
- **Save and use for all videos of this assay** copies it to every session of that assay. Do this only if the camera did not move.

New sessions automatically start with the calibration and parameters of the last session of the same assay. A note on the result reminds you to check it.
