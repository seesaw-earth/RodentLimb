# RodentLimb iOS 1.4 — work log

Binding spec: `TASK_FIRST_SPEC.md`. Shared files (`Analysis/*`, `App/L10n.swift`, `Pose/PoseTypes.swift`,
`Pose/PoseModels.swift`, `Data/{Session,Recording,Experiment,PoseStorage,Exporter,StudyExport}.swift`) are not
edited; proposed changes are listed at the end.

## Status

| Priority | State |
|---|---|
| P1 Models | done |
| P2 Task-first navigation | done (UI written; not compiled with the iOS SDK) |
| P3 Never lose data | done (store + Settings screens) |
| P4 Remove decorative icons | done |
| P5 Visualisation | done (task Results charts; per-session cards unchanged apart from icons) |
| P6 Version / README | done (1.4.0, build 6; README.zh-Hans.md rewritten, README.md updated) |

Left for a Mac with Xcode: build once and fix whatever the iOS SDK reports in the SwiftUI layer.

## Log

### P1 Models
- `Pose/PoseDecoder.swift`: generalised to K keypoints with `PoseModelID.keypointMap` / `PoseOutputLayout`
  (26/27 channels for 7, 29/30 for 8); native `Float16` kept; bounds-checked tensor reads.
- `Pose/PoseEngine.swift`: per-model load + cache (`load(_:)`, `states`, `failure(_:)`, `trimMemory(keeping:)`),
  model URL per `PoseModelID.resourceName`; `PoseVideoProcessor.run(… modelID:)` writes `modelID.rawValue` into
  the track; `track.load(.isDecodable)` check with a clear message (`VideoCodec`). `kPoseModelName` stays
  "CylinderMousePoseV2" (shared files use it).
- `Data/RecordingSidecar.swift` (new): `Recordings/<id>/source.json`, the Mac's VideoSource format (mode
  "copied", fingerprint, poseModel; Mac-only fields round-trip). No sidecar = CylinderMousePoseV2 → re-tracked
  with `.runnable` (FP16). Verified: the Mac decoder reads it (core tests).
- `Data/ProcessingQueue.swift`: loads the video's own model; a model that cannot load fails that video with
  the reason and the queue goes on. `retry(recording:model:)`.
- Store: `poseModel(_:)`, `importVideo(… model:fingerprint:)`, `rerunDetection(_:model:)`, `finishProcessing`
  records the model from the track; fingerprints of pre-1.4 videos are back-filled in the background.
- Exports: `Data/ExportFixes.swift` post-processes the shared exporter's files (summary `model,` row and the
  methods sentence, like the Mac's ExportService). Used by the session export and the task export.
- UI: model picker in Add Videos (default `PoseModelID.defaultChoice`, warning when the task uses another
  model), "Track again ▸ model" in the video and session screens, default model in Settings.

### P2 Task-first
- Tabs Tasks · Processing · Settings (`RootView`, `AppModel`, `Route`).
- `Data/Tasks.swift` (Foundation only): `TaskRef (experimentID, assay)`, task list (legacy multi-assay
  studies → one task per assay), counts in one pass, `SessionState`, group → animal → session tree,
  `unassignedRecordings`, `taskPeers`. `TaskCatalog` = paradigms grouped by purpose with one-line text.
- Store: `createTask`, `editTask` (flush), groups add/rename/remove, `allocate`, `move(_:to:)` (Move to Task),
  `deleteTask` (single-paradigm study → whole study; legacy multi-paradigm study → only its sessions),
  `setParadigm` for 1.3 studies without one; sessions created at import (`assign` right after the recording);
  `assign` copies parameters/calibration only from the same task (never another task; none outside tasks);
  1.3 "planned" videos get their session on launch.
- UI: `TasksView` (+ New Task sheet: paradigm first, then name/groups/timepoints/note), `TaskView`
  (header, Add Videos, Sessions | Results | Design, Export), `TaskDesignView`, `TaskResultsView`,
  `AddVideosSheet` (replaces ImportSheet: per-video animal/group/timepoint/trial parsed from file and folder
  names via `Data/ImportNaming.swift`, folders, Photos, iPad drop, duplicates by fingerprint),
  `ProcessingView` (current, waiting, failed, "all tracked — next steps"), `VideoLists` (Needs review,
  Not in a task with Move to Task…, All videos). `DesignSheets.swift` keeps the reused StudyEditor (without
  the planned-tasks section), AnimalEditor and Randomize sheets. Removed: HomeView, LibraryView,
  StudyViews (lists/compare), ImportSheet, AssignTasksSheet.
- `Data/TaskExport.swift`: summary (shared groupCSV), QC table with pose model, events, time bins, methods
  (with model) + design, README, manifest — scoped to (experimentID, assay); blinding respected.
- ParamsSheet: Protocol picker (`Data/ParameterPresets.swift`, Mac copy) + "Apply to all sessions of this
  task"; CalibrationView "use for all sessions of this task" (store.applyToTask).

### P3 Never lose data
- `Data/LibrarySafety.swift` (Mac copy without the library lock): Recently Deleted (30 days) and metadata
  backups (14 daily + 10 others).
- Store: deletes move folders to Recently Deleted (after pending writes, on the IO queue) and return the
  entry id → Undo toast (`UndoToast` in RootView); `restoreDeleted`, `eraseDeleted`, `emptyRecentlyDeleted`,
  purge on launch; daily backup on launch, before deletes / bulk changes; `restoreBackup` (backs up first).
- Immediate flush: decisions, deletes, imports, task edits, re-track, Move to Task, apply-to-task.
- Background flush verified: `flushForBackground` (scene `.background`) + `flush` on `.inactive`.
- O(1) lookups: verified id → index maps (sessions, by-recording, recordings, experiments), rebuilt on
  structural changes or when a miss happens while the array has grown.
- Text fields: `CommitTextField` (Return, focus loss, disappear) in Design; exclusion reason saved as typed
  and flushed on disappear; edit sheets refuse swipe-to-dismiss while there are unsaved changes.
- Settings › Data: Recently Deleted and Backups screens.
- `Data/Coders.swift` (Coders moved out of SessionStore + `AppInfo`).

### P4 Icons
- `CardHeader` has no symbol any more; `AssayBadge`/`IconBadge` replaced by `AssayChip` (text on a tinted
  capsule); `Banner`/`NoteList` use a coloured bar / dots; toast is text only; QC verdict = dot + text;
  `EmptyState`, `SectionTitle`, `LimbGlyph`, `PressableCardStyle`, `brandGradient` removed (unused).
- All `Label(…, systemImage:)` in buttons, menus, rows, headers and banners replaced by text; menu
  checkmarks replaced by `Picker`s (system selection mark). Kept: tab bar symbols, playback controls
  (step / play / pause, play-from-event), the "+" New Task button (accessibility label).
- Onboarding: four text pages (app mark on the first only). No emoji in UI strings or READMEs (plain
  arrows "→" in text are kept as punctuation).
- `.fontDesign(.rounded)` removed everywhere (system font for data).

### P5 Visualisation
- `UI/TaskResultsView.swift`: group comparison (numeric x = group index + deterministic golden-ratio
  jitter; animal dots; mean = short thick bar; ± SEM whiskers with caps; n under each group; y title with
  unit; light grid only), stats table (n, mean, SD, SEM), course across timepoints (line + points +
  whiskers), binned time course per group (line + ± SEM band; behaviour bins or TST per minute).
  Okabe–Ito group colours (`Palette.group`, black → white in Dark Mode). Included sessions only,
  animals as the unit (shared `groupStats`). `Data/TaskStats.swift` holds the numbers (tested).

### P6
- MARKETING_VERSION 1.4.0, CURRENT_PROJECT_VERSION 6.
- `Tools/install_model.py` installs `--fp16` / `--nir` and removes a leftover CylinderMousePoseV2 package.


### Review fixes (after the independent review)
Mirrors the Mac's task semantics (TaskSupport.swift).
1. Move to Task: `moveToTask(_:task:from:) -> TaskMove` (+ `undoMove`). A video belongs to one study: when
   it joins another study its sessions of other paradigms go to Recently Deleted as one entry (no
   phantom task); within one study the `source` task's session goes. The video's current task is not
   offered in MoveToTaskSheet. Undo for every move (`AppModel.moved`, `UndoAction`).
2. `removeFromTask(_:task:)`: sessions to Recently Deleted (one entry); a video left without a session
   leaves the study (animal ID and group kept as text). Used by "Remove from task, keep the video".
3. `deleteTask(_:keepVideos:) -> TaskDeletion` (+ `undoDeleteTask`): a task alone in its study deletes
   the study; a paradigm of a multi-paradigm study is taken off the plan (order restored on Undo) and
   `removeFromTask` runs. The confirmation says which (`deletionPlan`); Undo is offered also without
   sessions.
4. QC is no longer re-run when a video leaves every task (only when it joins a study). Only the first
   QC of a tracking (or of a video that never had one) includes a passing video automatically.
   `DeletedEntry.Link` (iOS-only LibrarySafety) gained optional `decision` / `exclusionReason`,
   restored with the study.
5. Saving: `importVideo` flushes per video; coalescing has a ~2 s maximum delay; at launch a
   `Recordings/<id>/` folder without `recording.json` (interrupted import) goes to Recently Deleted,
   and restoring it brings the video back as an untracked video outside any task.
6. Group carried by a moved video (its animal's group in a non-blinded old task, or a free-text group)
   becomes the animal's group in a single-factor, non-blinded target (`setGroup`, adds the level).
7. Import: new animals and their groups in one `updateExperiment` (`prepareAnimals`, first group wins);
   `updateExperiment` re-syncs only recordings whose animal changed (all only for factor / blinding
   changes) — imports are linear.
8. Default animal IDs "M1", "M2", … (first free number in the task and the rows, any language).
9. Temporary copies: dismissal disabled while copying; leftovers removed on disappear and after each
   add (`Data/TempFiles.swift`, also the `<UUID>/` folders of PickedVideo); stale copies cleared while
   the library opens (app only, not in tests).
10. `setParadigm` creates the paradigm's session for every video of the study.
11. Performance: `sessions(in:)` keys computed once per session and cached against a library revision
    counter; Results compute their numbers only after a change (debounced 0.5 s, reading only results
    of sessions whose `updatedAt` changed; a newer change cancels the read); task names built once per
    list (Video lists, Processing); exclusion reason saved on Return / focus loss / disappear only.
12. Launch: the library is decoded and 1.2 libraries migrated off the main thread ("Opening library…");
    the queue starts after loading.
13. Smaller: swipe actions that open a confirmation use `.tint(.red)` without the destructive role;
    Photos `preferredItemEncoding: .current`; footer says folders come from Files (drops accept files);
    the Animals menu of Add Videos is hidden while blinded (it filled real IDs behind blind codes);
    unallocated animals are "Not allocated" (not "All animals") in tasks with groups.
- Core tests: 96 checks, all pass (moves, phantom-task regression, undo, removal, deletion plan,
  decisions kept, orphan import, batch animals, setParadigm sessions, async load).

## Verification done
- `swiftc -parse` on every .swift file: clean.
- Foundation layer type-checked with `-swift-version 5 -parse-as-library` (shared Analysis/Data/Pose + all
  iOS-only Data files + the real iOS `SessionStore.swift` with stand-ins for UIKit/Combine).
- `Tools/core_tests/run_core_tests.sh` (new): runs the real iOS store end to end on Linux (tasks, import,
  groups, synthetic pose → QC → analysis, results, task export, Recently Deleted, Move to Task, backups,
  legacy 1.3 studies, reload, lookups, naming). All pass.

- `sh /home/claude/out/RodentLimb-Mac/tools/verify_shared.sh RodentLimb` → all 25 shared files identical.

## Decisions
- Model per video in `source.json` (Mac-compatible) rather than a new file: one format for both apps.
- A task with only one paradigm is deleted as a whole study; a 1.3 study with several paradigms loses only
  that paradigm's sessions (videos stay for the other tasks).
- "Not in a task" = videos outside any study, in a missing study, or in a study without any session.
- Deleting a session offers "remove from task, keep the video" (removeFromTask; it then shows in Not in a task) or "delete session and video".
- The group a moved video carries becomes its animal's group in the target (Mac semantics).
- Each Results chart uses a numeric x axis (group index + golden-ratio jitter) so animals can be jittered.
- (Superseded by the review fixes: a paradigm of a 1.3 multi-paradigm study is removed with removeFromTask.)
- The default pose model is changed only in Settings (Add Videos does not overwrite it).
- `SessionStore.init(base:)` takes an optional library folder (tests only; the app uses Documents).

## Not verifiable here (no Apple SDK)
- All SwiftUI / Charts / AVFoundation / CoreML / Vision code was checked by reading only, in particular:
  `track.load(.isDecodable)` / `.formatDescriptions` (iOS 15+), `AxisValueLabel { }` content, `RuleMark(xStart:xEnd:y:)`,
  `AreaMark(x:yStart:yEnd:)` grouped by `foregroundStyle(by:)`, `.listSectionSpacing(.compact)` (iOS 17),
  `.dropDestination(for: PickedVideo.self)`, `fileImporter` with `.folder` (folder enumeration under the
  folder's security scope), `ContentUnavailableView { } description: { }` (iOS 17).
- The models were not run here (no Core ML): PalmReaderPose8's [1,29,8400] head goes through the same
  `PoseOutputLayout.detect` as on the Mac.

## Proposed shared-file changes (not applied — change both copies together)
1. `Data/Session.swift` (`Analyzer.run`): the info note "CylinderMousePoseV2 was trained on cylinder
   videos…" should name the visible-light model generically (or `PoseModelID(modelName: track.modelName)`),
   and not appear for PalmReaderPose8 tracks.
2. `Data/Exporter.swift`: `metadata(_:)` writes `("model", kPoseModelName)` and `methods(_:result:)` opens
   with `kPoseModelName`; both should take the model of the video (e.g. a `poseModel: PoseModelID`
   parameter, defaulting to `.visible`). Both apps currently correct the text afterwards (Mac
   ExportService, iPhone `ExportFixes`). `groupCSV` could gain a `pose_model` column.
3. `Pose/PoseModels.swift` header comment: the sidecar `source.json` is now written by the iPhone too.
4. `Data/Recording.swift` header comment still describes the 1.3 flow (import → QC → tasks); 1.4 creates
   the session at import.
5. `SessionStatus.symbol`, `QCVerdict.symbol`, `Assay.symbol` (SF Symbol names) are no longer used by the
   iPhone UI; remove once the Mac drops them too.
