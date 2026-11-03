# iPhone & iPad

RodentLimb is one app on the App Store for Mac, iPhone and iPad. The iPhone and iPad app is suited to analysing a few videos at the bench; the Mac app to large batches of long videos.

## What is the same

- **The analyses.** Both apps compile the same analysis code: the same tasks, parameters, quality control, study design and exports. The same video and keypoints give the same measures.
- **The library format.** The folder layout and files (`Experiments/`, `Recordings/`, `Sessions/`, `pose.bin`) are the same. Copy the iPhone's RodentLimb folder (Files › On My iPhone › RodentLimb) to the Mac and open it with **File › Open Library…**: studies, videos and results are all there. Videos that are inside the folder play directly.
- **The visible-light network.** The iPhone app runs this network in full precision (`CylinderMousePoseV2`); the Mac app's CylinderPose7 is the same network with half-precision weights, so keypoints differ by rounding only. See [Models & provenance](../models/).

## What differs on the Mac

- Import whole folders by drag and drop, with naming rules and duplicate detection.
- A processing queue with checkpoints, automatic retries and overnight safeguards ([Processing queue](./processing.md)).
- Keyboard review ([Keyboard shortcuts](./shortcuts.md)), native tables and an inspector.
- Export of a whole study or library at once, including BORIS, DeepEthogram and DeepLabCut formats ([Export](./export.md)).
- The near-infrared model, PalmReaderPose8.
- Recently Deleted, automatic backups and a warning when two Macs open the same library ([Library & files](../reference/files.md)).

The Mac app does not record video and does not render videos with the skeleton drawn on them.
