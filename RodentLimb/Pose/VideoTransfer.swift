import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// A video received from Photos or by drag and drop. The provider's temporary URL may disappear
// after loading, so it is copied at once (into its own folder, keeping the original file name,
// from which the animal ID is suggested).
struct PickedVideo: Transferable {
    let url: URL
    var originalName: String { url.lastPathComponent }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let name = received.file.lastPathComponent.isEmpty ? "video.mov" : received.file.lastPathComponent
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedVideo(url: target)
        }
    }
}
