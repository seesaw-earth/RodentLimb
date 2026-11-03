// Coders.swift — JSON coders of the library files and the app's name / version (iPhone only;
// Foundation only, so the data layer can be compiled and tested without UIKit).

import Foundation

/// JSON coders for session.json, recording.json, result.json and studies. Non-finite numbers (a
/// measure that is NaN or infinite) are written as strings: with the default strategy
/// JSONEncoder throws, and until 1.2.1 that silently prevented the whole file from being saved.
enum Coders {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}

enum AppInfo {
    static let name = "RodentLimb"
    /// "1.4.0 (6)".
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
