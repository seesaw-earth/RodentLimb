# Processing queue

Tracking runs in a queue, one pose-model pass per video. Everything after that (quality control, scoring, review) works from the stored keypoints and never needs the model again.

## The Processing page

Open **Processing** in the sidebar (⌘2). It shows:

- the video being tracked, about once a second, with its keypoints drawn on it;
- progress, frames per second and the time left for this video and for the whole queue;
- which model each video uses, and which videos wait, failed or are offline.

You can **pause** (⌘.) and **start** (⌘R) the queue, move a video to the front or back (⌥⌘↑ / ⌥⌘↓) and cancel single videos. 1–3 videos are tracked at the same time (*Videos processed at the same time*, in Settings › Processing). **Retry Failed Videos** queues failed videos again; each continues from its checkpoint. The Dock icon shows the overall progress, and a notification arrives when the queue is done.

When every video is tracked, the page says so and offers the next steps: videos that need a QC decision (**Review Now**), included videos without a task (**Assign Tasks…**) and analyses that are ready (**Open Analyses**).

## Why a batch does not crash or start over

- **Frame-by-frame checkpoints.** Keypoints are written to disk as they are computed, at least every 2 seconds. After a pause, a quit, a crash, a sleeping laptop or a power cut, tracking continues after the last saved frame. A resumed run gives bit-for-bit the same keypoints as an uninterrupted one.
- **One bad video does not stop the batch.** Decoding or Core ML errors are retried from the checkpoint up to 3 times; a video that still fails is marked *Failed* with the reason, and the queue moves on. A video whose codec cannot be decoded fails at once, without retries.
- **No crash loops.** If the app quits unexpectedly twice while tracking the same video, that video is set aside with an explanation.
- **Offline drives.** Videos on a disconnected drive stay in the queue as *offline*; the others continue, and they finish when the drive is back.
- **Disk space.** When less than 300 MB is free, the queue pauses instead of failing videos.
- **Quitting.** Quitting during tracking asks first; the running videos stop at the current frame and continue next time. Closing the window does not quit the app; tracking continues in the background.
- **Sleep and App Nap.** While tracking, the Mac does not go to sleep from inactivity (the display still can; turn off *Keep the Mac awake while tracking* in Settings to allow sleep), and the app is not slowed by App Nap.
- **Steady memory.** Only the keypoints are kept in memory, so hours-long videos do not make memory grow.

Every import, video, failure and recovery is written to the activity log (**Show Activity Log**).

## Intel and Apple silicon

Both are supported and give the same keypoints. Apple silicon runs the models on the Neural Engine and is much faster. On Intel Macs, half-precision model outputs are converted bit by bit, with identical values.
