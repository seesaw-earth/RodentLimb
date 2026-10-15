// OnboardingView.swift — three short pages shown on first launch (and from Settings).
// Kept to what a new user needs before importing a video: what the app does, how to film,
// and that data never leaves the phone.

import SwiftUI

@MainActor
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let symbol: String?
        let title: String
        let text: String
    }

    private var pages: [Page] {
        [
            Page(symbol: nil,
                 title: L("Welcome to RodentLimb", "欢迎使用 RodentLimb"),
                 text: L("Tracks the four paws, nose and tail base in your videos, then scores tail suspension, cylinder and gait tests on your iPhone.",
                         "识别视频中小鼠的四只爪、鼻尖和尾根，在 iPhone 上完成悬尾、圆筒和步态实验的分析。")),
            Page(symbol: "video.badge.checkmark",
                 title: L("Film for good tracking", "拍摄要点"),
                 text: L("One mouse per video, fixed camera, even light. Cylinder and gait: film from below through a clear floor. Gait: 60 fps or more.",
                         "每段视频一只小鼠，相机固定，光线均匀。圆筒和步态：透过透明底面从下方拍摄。步态：60 fps 以上。")),
            Page(symbol: "lock.shield",
                 title: L("Private by design", "数据只在本机"),
                 text: L("Videos and results stay on this device. Change any parameter later — results update instantly without re-running the model.",
                         "视频和结果只保存在本机。之后可随时调整参数，结果即时更新，无需重新运行模型。")),
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
            if let symbol = p.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(Palette.brandGradient)
                    .frame(height: 150)
            } else {
                AppMark(size: 150)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 20, y: 10)
            }
            Text(p.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
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
