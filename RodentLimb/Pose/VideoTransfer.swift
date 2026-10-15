import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// PhotosPicker's temporary URL may disappear after loading: copy it immediately.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let extensionName = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(extensionName)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedVideo(url: target)
        }
    }
}
