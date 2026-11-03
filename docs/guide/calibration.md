# Calibration

Calibration tells RodentLimb where the apparatus is in the picture. It is needed for the **cylinder test**, optional for **gait**, and not used by the other tasks.

Open it from the analysis (**Calibration**). It opens in its own window, on a frame of the video.

## Working with the frame

- Pick a **calibration frame** with the time slider, or step ±1 s, to a moment where the apparatus is clearly visible.
- **Show keypoints of this frame** draws the tracked points to help you place the marks.
- Drag the handles with the mouse; a **loupe** magnifies the point under the cursor while you drag. Nudge a selected handle with the arrow keys, or type exact values (in video pixels).

## Cylinder, bottom view: the rim circle

Match the circle to the inner rim of the cylinder floor: drag inside it to move it, drag its edge to resize it. The inner dashed circle shows the **wall zone**: a still forepaw between the two circles counts as being on the wall.

**Auto-fit from Tracking** fits the circle to where the keypoints went during the video. The mouse explores the whole floor, so this is usually a good start. It is available once the video has been tracked.

## Cylinder, side view: the floor line

Choose **Side view** under *Camera* and drag the dashed line onto the cylinder floor. **Estimate from Hind Paws** places it at the lowest hind-paw positions. A forepaw raised above the line by the *paw height* parameter counts as raised.

## Gait: the cm ruler

Drag both ends onto marks a known distance apart (a ruler, or the walkway width) and enter the **known distance**. The window shows the resulting scale in px/cm. **Remove Scale** reports lengths in body lengths again.

## One camera position, many videos

**Save** stores the calibration for this analysis and recomputes it. **Save and Use for All** also applies it to the other analyses of this task in the study; use it only when the camera did not move. A note on each of those results says which video the calibration was copied from, so you can check it.
