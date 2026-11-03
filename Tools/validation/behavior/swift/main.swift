import Foundation

func loadTrack(_ path: String) -> PoseTrack {
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    var lines = text.split(separator: "\n")
    lines.removeFirst()
    var times: [Double] = []
    var t = PoseTrack(width: 640, height: 480, fps: 30, duration: 0, modelName: "sim", modelVersion: "0")
    for line in lines {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map { Double($0) ?? -1 }
        times.append(f[1]); t.boxConfidence.append(Float(f[2]))
        for k in Kp.allCases {
            let b = 3 + k.rawValue * 3
            t.x[k.rawValue].append(Float(f[b])); t.y[k.rawValue].append(Float(f[b + 1])); t.c[k.rawValue].append(Float(f[b + 2]))
        }
    }
    t.times = times
    let fps = times.count > 1 ? 1 / (times[1] - times[0]) : 30
    t.fps = fps
    t.duration = (times.last ?? 0) + 1 / fps
    return t
}

struct Out: Encodable {
    var metrics: [String: Double?]
    var events: [[String: String]]
    var notes: [String]
    var tracks: [String: [[Double]]]
    var bins: [String: [Double]]
}

func dump(_ name: String, _ r: AnalysisResult, _ dir: String) {
    var m: [String: Double?] = [:]
    for x in r.metrics { m[x.key] = x.value }
    let ev = (r.behavior?.events ?? []).map { e -> [String: String] in
        ["id": "\(e.id)", "onset": String(format: "%.3f", e.onset), "offset": String(format: "%.3f", e.offset), "label": e.label,
         "counted": e.counted ? "1" : "0", "info": e.info ?? ""]
    }
    var tr: [String: [[Double]]] = [:]
    for t in r.behavior?.tracks ?? [] { tr[t.key] = t.intervals.map { [$0.start, $0.end] } }
    var bins: [String: [Double]] = [:]
    for b in r.behavior?.bins ?? [] { bins[b.key] = b.values }
    let o = Out(metrics: m, events: ev, notes: r.notes.map { "[\($0.level.rawValue)] " + $0.text.en }, tracks: tr, bins: bins)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try! enc.encode(o).write(to: URL(fileURLWithPath: "\(dir)/\(name)_swift.json"))
}

let dir = CommandLine.arguments[1]
let modelPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let common = CommonParams()

do {
    let tr = loadTrack(dir + "/itch_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var p = ItchParams(); p.windowEnd = tr.duration; p.binSize = 30; p.method = .rules
    let t0 = Date()
    let r = ItchAnalyzer.run(track: tr, series: s, params: p, overrides: [:], model: nil)
    print("itch rules", String(format: "%.2f s", Date().timeIntervalSince(t0)))
    dump("itch", r, dir)
    if !modelPath.isEmpty, let m = ScratchModel(url: URL(fileURLWithPath: modelPath)) {
        p.method = .auto
        dump("itch_model", ItchAnalyzer.run(track: tr, series: s, params: p, overrides: [:], model: m), dir)
    }
    // Reviewer edit: ignore the first bout → one fewer bout, edited_n = 1
    if let first = r.behavior?.events.first {
        dump("itch_edit", ItchAnalyzer.run(track: tr, series: s, params: p, overrides: [first.id: "ignore"], model: nil), dir)
    }
}
do {
    let tr = loadTrack(dir + "/cheek_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var p = ItchParams(); p.windowEnd = tr.duration; p.binSize = 30; p.method = .rules; p.site = .cheek
    dump("cheek", ItchAnalyzer.run(track: tr, series: s, params: p, overrides: [:], model: nil), dir)
}
do {
    let tr = loadTrack(dir + "/pain_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var p = PainParams(); p.injectedPaw = .rightHind; p.phase1End = 120; p.phase2Start = 180; p.phase2End = 480; p.binSize = 60
    let t0 = Date()
    dump("pain", PainAnalyzer.run(track: tr, series: s, params: p, overrides: [:]), dir)
    print("pain", String(format: "%.2f s", Date().timeIntervalSince(t0)))
}
do {
    let tr = loadTrack(dir + "/groom_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var p = GroomingParams(); p.windowEnd = tr.duration; p.binSize = 60
    let t0 = Date()
    dump("groom", GroomingAnalyzer.run(track: tr, series: s, params: p, overrides: [:]), dir)
    print("groom", String(format: "%.2f s", Date().timeIntervalSince(t0)))
}
do {
    let tr = loadTrack(dir + "/seizure_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var p = SeizureParams(); p.injectionTime = 60; p.windowEnd = tr.duration - 60; p.scoreArrest = true
    let t0 = Date()
    dump("seizure", SeizureAnalyzer.run(track: tr, series: s, params: p, overrides: [:]), dir)
    p.scale = .racineKainate
    dump("seizure_ka", SeizureAnalyzer.run(track: tr, series: s, params: p, overrides: [:]), dir)
    print("seizure", String(format: "%.2f s", Date().timeIntervalSince(t0)))
}

do {
    let tr = loadTrack(dir + "/control_pose.csv")
    let s = PoseSeries(track: tr, params: common)
    var a = ItchParams(); a.windowEnd = tr.duration; a.method = .rules
    dump("control_itch", ItchAnalyzer.run(track: tr, series: s, params: a, overrides: [:], model: nil), dir)
    a.site = .cheek
    dump("control_cheek", ItchAnalyzer.run(track: tr, series: s, params: a, overrides: [:], model: nil), dir)
    var b = PainParams(); b.phase1End = 100; b.phase2Start = 100; b.phase2End = tr.duration
    dump("control_pain", PainAnalyzer.run(track: tr, series: s, params: b, overrides: [:]), dir)
    var c = SeizureParams(); c.injectionTime = 0; c.windowEnd = tr.duration
    dump("control_seizure", SeizureAnalyzer.run(track: tr, series: s, params: c, overrides: [:]), dir)
    var g = GroomingParams(); g.windowEnd = tr.duration
    dump("control_groom", GroomingAnalyzer.run(track: tr, series: s, params: g, overrides: [:]), dir)
}
