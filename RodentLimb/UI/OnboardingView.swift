// OnboardingView.swift — four short text pages shown on first launch (and from Settings): what the
// app does, the task-first flow, how to film, and that nothing is lost.

import SwiftUI

@MainActor
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let title: String
        let text: String
    }

    private var pages: [Page] {
        [
            Page(title: L("Welcome to RodentLimb", "欢迎使用 RodentLimb"),
                 text: L("Tracks the four paws, nose and tail base in your videos and scores gait, cylinder and tail suspension tests, itch, spontaneous pain, grooming and seizures, on this device.",
                         "识别视频中小鼠的四只爪、鼻尖和尾根，在本机完成步态、圆筒和悬尾实验，以及瘙痒、自发痛、理毛和癫痫发作的评分。")),
            Page(title: L("Task first, then videos", "先建任务，再添加视频"),
                 text: L("Create a task: choose the paradigm and the groups. Add its videos: each one is tracked once, checked for quality, and the groups are compared as soon as results arrive.",
                         "新建任务：选择范式和分组。添加该任务的视频：每段视频只识别一次并检查质量，结果出来后立即按组比较。")),
            Page(title: L("Film for good tracking", "拍摄要点"),
                 text: L("One mouse per video, fixed camera, even light. Film from below through a clear floor. Gait, scratching and flinching: 60 fps or more. For dark boxes filmed in near-infrared, choose the near-infrared model when adding the videos.",
                         "每段视频一只小鼠，相机固定，光线均匀，透过透明底面从下方拍摄。步态、抓挠和甩爪：60 fps 以上。暗箱中用近红外拍摄的视频，添加时请选择近红外模型。")),
            Page(title: L("Nothing is lost", "数据不会丢失"),
                 text: L("Everything stays on this device and is saved as you work. Deleted items can be restored for 30 days, and the design and decisions are backed up every day.",
                         "所有数据只保存在本机，并在操作时随时保存。删除的内容 30 天内可以恢复，设计和决定每天自动备份。")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(Motion.gentle) { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? L("Continue", "继续") : L("Get started", "开始使用"))
                    .frame(maxWidth: .infinity)
            }
            .primaryAction()
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button(L("Skip", "跳过")) { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
                .opacity(page < pages.count - 1 ? 1 : 0)
        }
        .background(Palette.canvas)
        .interactiveDismissDisabled()
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            if p.title == pages.first?.title {
                AppMark(size: 120)
            }
            Text(p.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(p.text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Spacer(minLength: 40)
        }
    }
}
