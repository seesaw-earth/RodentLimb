# Data, groups & export

## The Data tab

All sessions in one list.

- **Filter** by assay (All, TST, CYL, GAIT) and **search** by subject, group or file name.
- **Swipe left** on a row to delete it.
- **Select** turns on multi-selection for export or deletion.
- **Compare groups** (when an assay is selected) opens the group comparison.

## Group comparison

Pick a measure. The chart shows the mean of each group (bar), the SEM (whisker) and each animal (dot), with a table of n, mean, SD and SEM. It is descriptive only: run statistics in your usual software on the exported CSV. Animals are grouped by the **Group** field entered for each session.

## Export one session

From a session, tap **Export**. You get:

- `…_summary.csv`: session information, every measure (key, value, unit) and the notes;
- the events of the assay: immobility bouts and a per-minute profile, cylinder contacts, or gait strides and footprints;
- `…_methods.txt`: a methods paragraph with your parameter values and references;
- optionally `…_pose.csv`: every frame, with x, y and confidence of each keypoint;
- optionally the skeleton MP4, if it was rendered.

All exports are **in English**, whatever the interface language, so they can go straight into scripts and papers. Columns are listed in [Files & exports](../reference/files.md).

## Export many sessions

In the Data tab, tap **Select**, choose sessions, then **Export CSV**. You get **one wide CSV per assay** with one row per animal (subject, group, video, date, status, then every measure). This is the format most statistics software expects.

## Where the files are

Everything is stored in the app's folder, visible in **Files › On My iPhone › RodentLimb**. Each session has its own folder with the video, the pose data and the result. See [Files & exports](../reference/files.md).
