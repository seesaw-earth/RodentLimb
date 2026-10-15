// LiveProgress.swift — observes only the running video's progress, so progress text and rings
// update without redrawing the screens around them.

import SwiftUI

@MainActor
struct LiveProgress<Content: View>: View {
    @ObservedObject var progress: ProgressInfo
    @ViewBuilder var content: (ProgressInfo) -> Content
    var body: some View { content(progress) }
}
