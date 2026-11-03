// SystemIntegration.swift — what a long batch needs from macOS:
//  • keep the Mac awake and out of App Nap while videos are processed (ProcessInfo activity:
//    user-initiated, idle system sleep disabled — the display may still sleep);
//  • progress bar and badge on the Dock icon (visible when the window is hidden);
//  • a notification when the batch is done (or when it needs attention).

import AppKit
import UserNotifications
import SystemConfiguration

@MainActor
final class SystemIntegration {
    private var activity: NSObjectProtocol?
    private var dockView: DockProgressView?

    /// Simultaneous videos suggested for this Mac: 2 on Apple silicon with ≥ 16 GB, else 1.
    nonisolated static var recommendedSimultaneous: Int {
        #if arch(arm64)
        return ProcessInfo.processInfo.physicalMemory >= 16 * 1_073_741_824 ? 2 : 1
        #else
        return 1
        #endif
    }

    /// "Ziqing's MacBook Pro" — shown when the library is open on another Mac. Read from the system
    /// configuration (no network lookup, unlike Host.current(), which can stall when DNS is slow).
    nonisolated static let computerName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"

    func setWorking(_ working: Bool, preventSleep: Bool) {
        if working {
            guard activity == nil else { return }
            var options: ProcessInfo.ActivityOptions = [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled]
            if preventSleep { options.insert(.idleSystemSleepDisabled) }
            activity = ProcessInfo.processInfo.beginActivity(options: options, reason: "RodentLimb is tracking videos")
        } else if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    func setDockProgress(_ fraction: Double?, queued: Int) {
        let tile = NSApp.dockTile
        if let f = fraction {
            if dockView == nil {
                let v = DockProgressView(frame: NSRect(origin: .zero, size: tile.size))
                dockView = v
                tile.contentView = v
            }
            dockView?.fraction = f
        } else if dockView != nil {
            dockView = nil
            tile.contentView = nil
        }
        tile.display()
    }

    /// Number of videos waiting for a QC decision on the Dock icon.
    func setBadge(_ n: Int) {
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyBatchFinished(_ s: BatchSummary) {
        let content = UNMutableNotificationContent()
        content.title = L("Tracking finished", "识别完成")
        var parts = [String(format: L("%d video(s) done", "%d 个视频完成"), s.finished)]
        if s.failed > 0 { parts.append(String(format: L("%d failed", "%d 个失败"), s.failed)) }
        if s.needsReview > 0 { parts.append(String(format: L("%d need QC review", "%d 个待 QC 复核"), s.needsReview)) }
        content.body = parts.joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "batch-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }
}

/// App icon with a progress bar along the bottom (Dock tile content view).
final class DockProgressView: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let f = max(0, min(1, fraction.isFinite ? fraction : 0))
        let inset = bounds.width * 0.12
        let barHeight = max(6, bounds.height * 0.09)
        let track = NSRect(x: inset, y: bounds.height * 0.08, width: bounds.width - 2 * inset, height: barHeight)
        let radius = barHeight / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let fill = NSRect(x: track.minX + 1.5, y: track.minY + 1.5,
                          width: max(barHeight - 3, (track.width - 3) * CGFloat(f)), height: track.height - 3)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: (barHeight - 3) / 2, yRadius: (barHeight - 3) / 2).fill()
    }
}
