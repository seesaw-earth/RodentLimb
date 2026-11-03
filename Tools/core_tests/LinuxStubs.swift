// LinuxStubs.swift — stand-ins for the Combine / UIKit / AVFoundation symbols SessionStore uses, so the
// data layer compiles and runs on Linux (Tools/core_tests/run_core_tests.sh).
import Foundation
// Stand-ins for Combine / UIKit / AVFoundation symbols used by SessionStore (type checking on Linux).
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
struct UIBackgroundTaskIdentifier: Equatable { static let invalid = UIBackgroundTaskIdentifier() }
@MainActor final class UIApplication {
    static let shared = UIApplication()
    func beginBackgroundTask(withName: String?, expirationHandler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {}
}
enum PoseVideoProcessor { static func firstFrameTime(url: URL) async -> Double? { nil } }
let kPoseModelName = "CylinderMousePoseV2"
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
