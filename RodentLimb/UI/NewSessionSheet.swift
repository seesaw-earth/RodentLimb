// NewSessionSheet.swift — pick an assay, add videos, optionally name the group, start.
// A native grouped form keeps it calm; recording tips are one tap away instead of always shown.
// Pose detection starts immediately in the background queue; calibration and parameters can be
// set afterwards (results update instantly without re-running the model).

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private struct PendingVideo: Identifiable {
    let id = UUID()
    var url: URL
    var subject: String
    var source: String
}

@MainActor
struct NewSessionSheet: View {
    let initialAssay: Assay

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    /// Return moves through the subject IDs, then to the group, then closes the keyboard.
    private enum Field: Hashable { case subject(UUID), group, notes }

    @State private var assay: Assay = .tailSuspension
    @State private var videos: [PendingVideo] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var loadingPhotos = 0
    @State private var showFiles = false
    @State private var group = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    assayPicker
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                    DisclosureGroup(L("Recording tips", "拍摄要点")) {
                        Text(assay.cameraTip.text).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                } header: {
                    Text(L("Assay", "实验范式"))
                }

                Section {
                    ForEach($videos) { $v in
                        HStack(spacing: 12) {
                            Image(systemName: "film").foregroundStyle(Palette.assay(assay)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                TextField(L("Subject ID", "动物编号"), text: $v.subject)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.body.weight(.semibold))
                                    .focused($focus, equals: .subject(v.id))
                                    .submitLabel(.next)
                                    .onSubmit { focusAfter(v.id) }
                                Text(v.source)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { videos.remove(atOffsets: $0) }
                    if loadingPhotos > 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(String(format: L("Copying %d videos…", "正在复制 %d 个视频…"), loadingPhotos))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Menu {
                        Button { showPhotos = true } label: { Label(L("From Photos", "从照片选取"), systemImage: "photo.on.rectangle") }
                        Button { showFiles = true } label: { Label(L("From Files", "从文件选取"), systemImage: "folder") }
                    } label: {
                        Label(videos.isEmpty ? L("Add videos", "添加视频") : L("Add more", "继续添加"), systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                } header: {
                    Text(L("Videos", "视频"))
                } footer: {
                    Text(L("One mouse per video. Add several to analyze a whole cohort; swipe left to remove one.",
                           "每段视频一只小鼠。可一次添加多段批量分析；左滑可移除。"))
                }

                Section {
                    TextField(L("Group, e.g. Vehicle", "组别，如 Vehicle"), text: $group)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .group)
                        .submitLabel(.next)
                        .onSubmit { focus = .notes }
                    if !store.knownGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(store.knownGroups.prefix(12), id: \.self) { g in
                                    Button(g) { group = g; focus = nil }
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(group == g ? Color.accentColor.opacity(0.18) : Palette.inset, in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    TextField(L("Notes", "备注"), text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focus, equals: .notes)
                } header: {
                    Text(L("Optional", "可选"))
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("New analysis", "新建分析"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done", "完成")) { focus = nil }.fontWeight(.semibold)
                }
            }
            .chromeBar(.bottom) { if focus == nil { startBar } }
            .onAppear { assay = initialAssay }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 30, matching: .videos)
            .onChange(of: photoItems) { _, items in loadPhotos(items) }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): for u in urls { addFile(u) }
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
        .interactiveDismissDisabled(!videos.isEmpty)
    }

    private var assayPicker: some View {
        HStack(spacing: 8) {
            ForEach(Assay.allCases) { a in
                Button {
                    withAnimation(Motion.snappy) { assay = a }
                } label: {
                    VStack(spacing: 8) {
                        AssayBadge(assay: a, size: 38)
                            .opacity(assay == a ? 1 : 0.55)
                        Text(a.name.text).font(.footnote.weight(.semibold))
                            .foregroundStyle(assay == a ? Color.primary : Color.secondary)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .background(assay == a ? Palette.assay(a).opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(assay == a ? Palette.assay(a) : Color.clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(assay == a ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: assay)
    }

    private var startBar: some View {
        Button {
            start()
        } label: {
            Group {
                if importing {
                    ProgressView()
                } else {
                    Text(videos.count > 1 ? String(format: L("Analyze %d videos", "分析 %d 个视频"), videos.count) : L("Analyze", "开始分析"))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .primaryAction(Palette.assayFill(assay))
        .disabled(videos.isEmpty || loadingPhotos > 0 || importing)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func focusAfter(_ id: UUID) {
        if let i = videos.firstIndex(where: { $0.id == id }), i + 1 < videos.count {
            focus = .subject(videos[i + 1].id)
        } else {
            focus = .group
        }
    }

    private func nextSubject(_ stem: String?) -> String {
        if let stem, !stem.isEmpty { return stem }
        return String(format: L("Mouse %d", "小鼠 %d"), videos.count + 1)
    }

    private func addFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
            videos.append(PendingVideo(url: tmp, subject: nextSubject(url.deletingPathExtension().lastPathComponent),
                                       source: url.lastPathComponent))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingPhotos += items.count
        let batch = items
        photoItems = []
        Task { @MainActor in
            for item in batch {
                do {
                    if let v = try await item.loadTransferable(type: PickedVideo.self) {
                        videos.append(PendingVideo(url: v.url, subject: nextSubject(nil), source: L("From Photos", "来自照片")))
                    }
                } catch {
                    self.error = error.localizedDescription
                }
                loadingPhotos -= 1
            }
        }
    }

    private func start() {
        importing = true
        UserDefaults.standard.set(assay.rawValue, forKey: SettingsKey.lastAssay)
        var created: [Session] = []
        for v in videos {
            do {
                created.append(try store.importVideo(from: v.url, assay: assay, subject: v.subject.trimmingCharacters(in: .whitespaces),
                                                     group: group.trimmingCharacters(in: .whitespaces), notes: notes))
                try? FileManager.default.removeItem(at: v.url)
            } catch {
                self.error = error.localizedDescription
            }
        }
        importing = false
        guard !created.isEmpty else { return }
        app.queue.kick()
        dismiss()
        if created.count == 1, let s = created.first {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                app.open(s.id)
            }
        }
    }
}
