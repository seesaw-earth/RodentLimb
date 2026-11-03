// ReviewOverlay.swift — what the review player shows for an analysis: calibration (cylinder rim /
// floor line), stance paws (gait), the state at the current time as chips (immobile / climbing,
// paw on wall, behavior events, time after injection) and the analysis' events on the timeline.
// Same rules as the iPhone app's ReviewPlayer.

import SwiftUI

enum ReviewOverlay {
    static func decorations(session s: Session, result: AnalysisResult?) -> PlayerDecorations {
        var d = PlayerDecorations()
        if s.assay == .cylinder {
            if s.params.cylinder.view == .bottom { d.circle = s.calibration.circle } else { d.floorY = s.calibration.floorY }
            d.wallMargin = s.params.cylinder.wallMargin
        }
        if s.assay == .gait, let g = result?.gait {
            let swap = s.params.gait.swapLR
            d.emphasized = { t in
                var out = Set<Kp>()
                for paw in Kp.paws where (g.stances[paw.code] ?? []).contains(where: { t >= $0.start && t < $0.end }) {
                    out.insert(swap ? paw.mirrored : paw)
                }
                return out
            }
        }
        d.chips = { t in chips(session: s, result: result, time: t) }
        let (marks, rows) = timeline(session: s, result: result)
        d.marks = marks
        d.markRows = rows
        return d
    }

    static func chips(session s: Session, result: AnalysisResult?, time t: Double) -> [OverlayChip] {
        var out: [OverlayChip] = []
        switch s.assay {
        case .tailSuspension:
            guard let d = result?.tst else { break }
            if d.climbing.contains(where: { t >= $0.start && t < $0.end }) {
                out.append(OverlayChip(text: L("Climbing", "爬尾"), color: Palette.orange))
            } else if d.bouts.contains(where: { t >= $0.start && t < $0.end }) {
                out.append(OverlayChip(text: L("Immobile", "不动"), color: Palette.purple))
            } else {
                out.append(OverlayChip(text: L("Mobile", "挣扎"), color: Palette.green))
            }
        case .cylinder:
            guard let d = result?.cylinder else { break }
            if d.leftContacts.contains(where: { t >= $0.start && t < $0.end }) { out.append(OverlayChip(text: L("L on wall", "左爪触壁"), color: Palette.blue)) }
            if d.rightContacts.contains(where: { t >= $0.start && t < $0.end }) { out.append(OverlayChip(text: L("R on wall", "右爪触壁"), color: Palette.vermillion)) }
        case .gait:
            guard let g = result?.gait else { break }
            let codes = Kp.paws.filter { paw in (g.stances[paw.code] ?? []).contains { t >= $0.start && t < $0.end } }.map(\.code)
            if !codes.isEmpty { out.append(OverlayChip(text: L("Stance ", "支撑 ") + codes.joined(separator: " "), color: Color.black.opacity(0.55))) }
        case .itch, .pain, .grooming, .seizure:
            guard let d = result?.behavior else { break }
            for e in d.events where e.label != EventClass.ignore.key && t >= e.onset - 0.02 && t < max(e.offset, e.onset + 0.3) {
                let c = d.eventClass(e.label)
                out.append(OverlayChip(text: c.label.text, color: Palette.event(c.color)))
            }
            for tr in d.tracks where !d.classes.contains(where: { $0.key == tr.key }) {
                if tr.intervals.contains(where: { t >= $0.start && t < $0.end }) {
                    out.append(OverlayChip(text: tr.label.text, color: Palette.event(tr.color)))
                }
            }
            if d.origin > 0 {
                out.append(OverlayChip(text: String(format: L("%@ after injection", "注射后 %@"), Fmt.clock(max(0, t - d.origin))),
                                       color: Color.black.opacity(0.55)))
            }
        }
        return out
    }

    /// Events of the analysis as timeline marks (one row per behavior track / kind).
    static func timeline(session s: Session, result: AnalysisResult?) -> ([TimelineMark], Int) {
        guard let r = result else { return ([], 1) }
        var marks: [TimelineMark] = []
        var rows = 1
        switch s.assay {
        case .tailSuspension:
            if let d = r.tst {
                marks += d.bouts.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.purple, row: 0) }
                marks += d.climbing.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.orange, row: 1) }
                rows = 2
            }
        case .cylinder:
            if let d = r.cylinder {
                marks += d.leftContacts.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.left, row: 0) }
                marks += d.rightContacts.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.right, row: 1) }
                rows = 2
            }
        case .gait:
            if let g = r.gait {
                for (i, paw) in Kp.paws.enumerated() {
                    marks += (g.stances[paw.code] ?? []).map { TimelineMark(start: $0.start, end: $0.end, color: KeypointColors.color(paw), row: i) }
                }
                rows = 4
            }
        case .itch, .pain, .grooming, .seizure:
            if let d = r.behavior {
                let tracks = d.tracks.filter { !$0.intervals.isEmpty }
                for (i, tr) in tracks.prefix(6).enumerated() {
                    marks += tr.intervals.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.event(tr.color), row: i) }
                }
                rows = max(1, min(6, tracks.count))
            }
        }
        return (marks, rows)
    }
}
