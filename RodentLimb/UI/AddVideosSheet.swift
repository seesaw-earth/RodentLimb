// AddVideosSheet.swift — add videos to a task (the task's paradigm is fixed). Choose files or a
// folder (Files), videos from Photos, or drop them (iPad). Each video gets an animal ID (parsed from
// the file name: a registered ID wins, else the name), a group (menu of the task's groups; prefilled
// when the file or folder name contains a group name; animals already in the task keep their
// group), a timepoint and a trial. The pose model is chosen once for the batch. Duplicates of videos
// already in the library are recognised by fingerprint and skipped unless allowed.
// Add → each video becomes a session of the task at once and is queued for tracking.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// File extensions treated as videos inside a chosen folder.
private let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "3gp", "webm"]

private struct PendingVideo: Identifiable {
    let id = UUID()
    /// The app's temporary copy (moved into the library on Add).
    var url: URL
    /// Original file name, or "From Photos".
    var source: String
    var folders: [String]
    var animal: String
    var group: String
    var timepoint: String
    var trial: Int
    var fingerprint: VideoFingerprint.Info?
    var duplicate = false
}

@MainActor
struct AddVideosSheet: View {
    let task: TaskRef

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: UUID?

    @State private var videos: [PendingVideo] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var loading = 0
    @State private var model = PoseModelID.defaultChoice
    @State private var notes = ""
    @State private var error: String?
    @State private var importing = false
    @State private var addDuplicates = false
    @State private var dropTargeted = false
    /// Pose models already used by the task's videos (computed once, not on every keystroke).
    @State private var usedModels = Set<PoseModelID>()
    /// The sheet is gone: copies still arriving are deleted at once.
    @State private var closed = false

    private var experiment: Experiment? { store.experiment(task.experimentID) }
    private var groups: [String] { experiment.map { store.groupChoices($0) } ?? [] }
    private var timepoints: [String] { experiment?.timepoints ?? [] }
    private var toAdd: [PendingVideo] { videos.filter { addDuplicates || !$0.duplicate } }

    var body: some View {
        NavigationStack {
            Form {
                videoSection
                if videos.count > 1 && (!groups.isEmpty || !timepoints.isEmpty) { batchSection }
                modelSection
                Section {
                    TextField(L("Note for these videos (optional)", "这些视频的备注（可选）"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.danger) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Add Videos", "添加视频"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "取消")) { discardPending(); dismiss() }.disabled(importing || loading > 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done", "完成")) { focus = nil }.fontWeight(.semibold)
                }
            }
            .chromeBar(.bottom) { if focus == nil { addBar } }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 100, matching: .videos,
                          preferredItemEncoding: .current)
            .onChange(of: photoItems) { _, items in loadPhotos(items) }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): addFiles(urls)
                case .failure(let e): error = e.localizedDescription
                }
            }
            .dropDestination(for: PickedVideo.self) { items, _ in
                for v in items { appendVideo(tmp: v.url, original: URL(fileURLWithPath: v.originalName), folders: []) }
                return !items.isEmpty
            } isTargeted: { dropTargeted = $0 }
        }
        .interactiveDismissDisabled(!videos.isEmpty || importing || loading > 0)
        .onAppear {
            usedModels = Set(store.sessions(in: task).compactMap(\.recordingID).map { store.poseModel($0).runnable })
        }
        .onDisappear {
            // Whatever was not added is a temporary copy: remove it (also those still being copied).
            closed = true
            if !importing { discardPending() }
        }
    }

    // MARK: Sections

    private var videoSection: some View {
        Section {
            if videos.isEmpty && loading == 0 {
                Text(L("Choose the videos of this task. One mouse per video; the animal ID is read from the file name and can be changed.",
                       "选择本任务的视频。每段视频一只小鼠；动物编号从文件名读取，可以修改。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach($videos) { $v in
                VideoRow(video: $v, experiment: experiment, groups: groups, timepoints: timepoints, focus: $focus) {
                    focusAfter(v.id)
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { videos[$0].url }
                videos.remove(atOffsets: offsets)
                for u in removed { TempFiles.remove(u) }
            }
            .deleteDisabled(importing)
            if loading > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(format: L("Copying %d videos…", "正在复制 %d 个视频…"), loading))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(L("From Files", "从文件")) { showFiles = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("From Photos", "从照片")) { showPhotos = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            let dups = videos.filter(\.duplicate).count
            if dups > 0 {
                Toggle(String(format: L("Add %d duplicates anyway", "仍然添加 %d 个重复视频"), dups), isOn: $addDuplicates)
            }
        } header: {
            HStack {
                Text(String(format: L("Videos (%d)", "视频（%d）"), videos.count))
                Spacer()
                Text(task.assay.name.text)
            }
        } footer: {
            Text(dropTargeted ? L("Drop to add.", "松开即可添加。")
                 : L("Choose a folder with From Files. On iPad, video files can also be dropped here. Swipe left to remove a video. Videos already in the library are marked and skipped.",
                     "选择文件夹请用“从文件”。在 iPad 上也可以把视频文件拖到这里。左滑可移除视频。已在资料库中的视频会被标出并跳过。"))
        }
    }

    private var batchSection: some View {
        Section {
            if !groups.isEmpty {
                Menu {
                    ForEach(groups, id: \.self) { g in
                        Button(g) { for i in videos.indices where !isRegistered(videos[i].animal) { videos[i].group = g } }
                    }
                    Button(L("No group", "不分组")) { for i in videos.indices where !isRegistered(videos[i].animal) { videos[i].group = "" } }
                } label: {
                    menuRow(L("Group of all new animals", "所有新动物的分组"), value: L("Choose", "选择"))
                }
            }
            if !timepoints.isEmpty {
                Menu {
                    ForEach(timepoints, id: \.self) { tp in
                        Button(tp) { for i in videos.indices { videos[i].timepoint = tp } }
                    }
                } label: {
                    menuRow(L("Timepoint of all videos", "所有视频的时间点"), value: L("Choose", "选择"))
                }
            }
        } header: {
            Text(L("For all videos", "批量设置"))
        }
    }

    private func menuRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        let used = usedModels
        Section {
            Picker(L("Pose model", "姿态模型"), selection: $model) {
                ForEach(PoseModelID.choices) { m in Text(m.shortTitle.text).tag(m) }
            }
        } header: {
            Text(L("Pose model", "姿态模型"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.detail.text)
                if !used.isEmpty && !used.contains(model) {
                    Text(L("Other videos of this task use another model. Use the same model for every video of a task.",
                           "本任务的其他视频使用了另一个模型。同一任务的所有视频应使用同一个模型。"))
                        .foregroundStyle(Palette.warning)
                }
            }
        }
    }

    private var addBar: some View {
        Button {
            start()
        } label: {
            Group {
                if importing {
                    ProgressView()
                } else {
                    Text(toAdd.count == 1 ? L("Add 1 video", "添加 1 段视频") : String(format: L("Add %d videos", "添加 %d 段视频"), toAdd.count))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .primaryAction()
        .disabled(toAdd.isEmpty || loading > 0 || importing)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    private func isRegistered(_ code: String) -> Bool { experiment?.animal(code: code) != nil }

    private func focusAfter(_ id: UUID) {
        if let i = videos.firstIndex(where: { $0.id == id }), i + 1 < videos.count {
            focus = videos[i + 1].id
        } else {
            focus = nil
        }
    }

    /// "M1", "M2", …: the first number free in the task and in the rows (the same in every language).
    private func nextAnimalID() -> String {
        var taken = Set((experiment?.animals ?? []).map { $0.code.lowercased() })
        for v in videos { taken.insert(v.animal.trimmingCharacters(in: .whitespaces).lowercased()) }
        var n = 1
        while taken.contains("m\(n)") { n += 1 }
        return "M\(n)"
    }

    /// Adds a copied video with names suggested from its file and folder names.
    private func appendVideo(tmp: URL, original: URL?, folders: [String]) {
        guard !closed else { TempFiles.remove(tmp); return }
        let e = experiment
        let stem = original.map { ImportNaming.stem($0) }
        var animal = nextAnimalID()
        var timepoint = timepoints.first ?? ""
        var trial = 1
        var group = ""
        if let stem {
            let s = ImportNaming.suggest(stem: stem, folders: folders, pattern: NamePattern(),
                                         animals: e?.animals.map(\.code) ?? [], timepoints: timepoints)
            animal = s.animal
            if !s.timepoint.isEmpty { timepoint = s.timepoint }
            trial = s.trial ?? 1
            if !isRegistered(animal) { group = ImportNaming.group(stem: stem, folders: folders, groups: groups) }
        }
        let v = PendingVideo(url: tmp, source: original?.lastPathComponent ?? L("From Photos", "来自照片"), folders: folders,
                             animal: animal, group: group, timepoint: timepoint, trial: trial)
        videos.append(v)
        fingerprint(v.id, tmp)
    }

    /// Fingerprints the copy off the main thread and marks it when the library already has it.
    private func fingerprint(_ id: UUID, _ url: URL) {
        Task { @MainActor in
            let fp = await Task.detached(priority: .utility) { try? VideoFingerprint.make(url) }.value
            guard let fp, let i = videos.firstIndex(where: { $0.id == id }) else { return }
            videos[i].fingerprint = fp
            let key = fp.duplicateKey
            let inBatch = videos.contains { $0.id != id && $0.fingerprint?.duplicateKey == key }
            videos[i].duplicate = store.knownFingerprints.contains(key) || inBatch
        }
    }

    /// Copies picked files (and the videos inside picked folders) in the background (a large video,
    /// or one in iCloud Drive or on an external drive, takes seconds to copy).
    private func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        loading += urls.count
        Task { @MainActor in
            for url in urls {
                do {
                    for item in try await Self.copyToTemporary(url) {
                        appendVideo(tmp: item.tmp, original: item.original, folders: item.folders)
                    }
                } catch {
                    self.error = error.localizedDescription
                }
                loading -= 1
            }
        }
    }

    private struct Copied: Sendable {
        var tmp: URL
        var original: URL
        var folders: [String]
    }

    /// Coordinated copy into the temporary folder, so a file provider can download the file first.
    /// A folder is searched (two levels deep) for videos.
    nonisolated private static func copyToTemporary(_ url: URL) async throws -> [Copied] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[Copied], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let fm = FileManager.default
                var isDir: ObjCBool = false
                var sources: [(URL, [String])] = []
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let top = url.lastPathComponent
                    let level1 = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    for u in level1 {
                        if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                            let inner = ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [])
                                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                            for f in inner where videoExtensions.contains(f.pathExtension.lowercased()) {
                                sources.append((f, [u.lastPathComponent, top]))
                            }
                        } else if videoExtensions.contains(u.pathExtension.lowercased()) {
                            sources.append((u, [top]))
                        }
                    }
                } else {
                    sources = [(url, [url.deletingLastPathComponent().lastPathComponent])]
                }
                var out: [Copied] = []
                var firstError: Error?
                for (src, folders) in sources {
                    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + src.lastPathComponent)
                    var coordinationError: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: src, options: [], error: &coordinationError) { readURL in
                        do { try fm.copyItem(at: readURL, to: tmp) } catch { copyError = error }
                    }
                    if let e = coordinationError ?? copyError {
                        if firstError == nil { firstError = e }
                    } else {
                        out.append(Copied(tmp: tmp, original: src, folders: folders))
                    }
                }
                if out.isEmpty, let e = firstError { cont.resume(throwing: e) } else { cont.resume(returning: out) }
            }
        }
    }

    /// Removes the temporary copies of videos that were not added.
    private func discardPending() {
        let urls = videos.map(\.url)
        videos = []
        for u in urls { TempFiles.remove(u) }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loading += items.count
        let batch = items
        photoItems = []
        Task { @MainActor in
            for item in batch {
                do {
                    if let v = try await item.loadTransferable(type: PickedVideo.self) {
                        appendVideo(tmp: v.url, original: nil, folders: [])
                    }
                } catch {
                    self.error = error.localizedDescription
                }
                loading -= 1
            }
        }
    }

    private func start() {
        guard !importing else { return }
        importing = true
        error = nil
        let pending = toAdd
        let skipped = videos.filter { !addDuplicates && $0.duplicate }
        let noteText = notes
        let m = model
        let t = task
        // New animals and their groups in one change of the task (the first group given wins).
        store.prepareAnimals(pending.map { (code: $0.animal, group: $0.group) }, in: t.experimentID)
        Task { @MainActor in
            var added = 0
            for v in pending {
                do {
                    // The temporary copy is moved into the recording folder (instant, no extra space).
                    _ = try await store.importVideo(from: v.url, move: true, task: t, animalCode: v.animal, group: v.group,
                                                    timepoint: v.timepoint, trial: v.trial, notes: noteText, model: m,
                                                    fingerprint: v.fingerprint)
                    added += 1
                    videos.removeAll { $0.id == v.id }
                    TempFiles.remove(v.url)
                } catch {
                    self.error = error.localizedDescription
                }
            }
            store.flush()
            importing = false
            if closed { discardPending() }
            guard added > 0 else { return }
            queue.kick()
            if videos.allSatisfy({ v in skipped.contains { $0.id == v.id } }) {
                discardPending()
                dismiss()
                app.notice = added == 1 ? L("1 video added", "已添加 1 段视频") : String(format: L("%d videos added", "已添加 %d 段视频"), added)
            }
        }
    }
}

/// One video in the sheet: animal ID, group, timepoint, trial.
@MainActor
private struct VideoRow: View {
    @Binding var video: PendingVideo
    let experiment: Experiment?
    let groups: [String]
    let timepoints: [String]
    var focus: FocusState<UUID?>.Binding
    let next: () -> Void

    private var registered: Animal? { experiment?.animal(code: video.animal) }

    @ViewBuilder
    private var choices: some View {
        if !groups.isEmpty { groupControl }
        if !timepoints.isEmpty {
            Menu {
                Picker(L("Timepoint", "时间点"), selection: $video.timepoint) {
                    ForEach(timepoints, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                chip(video.timepoint.isEmpty ? L("Timepoint", "时间点") : video.timepoint, active: !video.timepoint.isEmpty)
            }
        }
    }

    private var trialStepper: some View {
        Stepper(value: $video.trial, in: 1...20) {
            Text(String(format: L("Trial %d", "第 %d 次"), video.trial)).font(.footnote).monospacedDigit()
        }
        .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Animal ID", "动物编号"), text: $video.animal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.weight(.semibold))
                    .focused(focus, equals: video.id)
                    .submitLabel(.next)
                    .onSubmit(next)
                // Not while blinded: the menu would fill in the real ID behind a blind code.
                if let e = experiment, !e.animals.isEmpty, !e.blinded {
                    Menu(L("Animals", "动物")) {
                        ForEach(e.animals) { a in
                            Button(a.code + (e.groupLabel(a).isEmpty ? "" : "  ·  " + e.groupLabel(a))) {
                                video.animal = a.code
                            }
                        }
                    }
                    .font(.footnote)
                }
            }
            // One line when it fits; on a narrow iPhone or with large text the trial stepper moves to
            // its own line instead of being pushed off the screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    choices
                    trialStepper
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) { choices }
                    trialStepper
                }
            }
            HStack(spacing: 6) {
                Text(video.source).lineLimit(1).truncationMode(.middle)
                if video.duplicate {
                    Text(L("Already in the library", "资料库中已有")).foregroundStyle(Palette.warning)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var groupControl: some View {
        if let a = registered, let e = experiment {
            // Animals already in the task keep their group.
            chip(e.blinded ? L("Registered", "已登记") : (e.groupLabel(a).isEmpty ? L("Not allocated", "未分组") : e.groupLabel(a)), active: false)
        } else {
            Menu {
                Picker(L("Group", "分组"), selection: $video.group) {
                    Text(L("No group", "不分组")).tag("")
                    ForEach(groups, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                chip(video.group.isEmpty ? L("Group", "分组") : video.group, active: !video.group.isEmpty)
            }
        }
    }

    private func chip(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .background(active ? Color.accentColor.opacity(0.12) : Palette.inset, in: Capsule())
    }
}
