import Foundation
import swift_polis

enum DatabaseState {
    case notReady
    case ready
}

final class DataBase {
    private(set) var state: DatabaseState = .notReady
    private let remotePath: String
    private let localPath: String
    private let loader: RemoteDownloader

    init(remotePath: String, localPath: String) {
        self.remotePath = remotePath
        self.localPath = localPath
        loader = RemoteDownloader(fromRemote: remotePath, toLocal: localPath)
        loader.downloadIfNeeded { [weak self] in
            self?.state = .ready
        }
    }

    func getLastUpdateTime() -> String {
        "ToDo date"
    }

    func getNumFascilities() -> String {
        "999"
    }

    func getByName(name: String) -> String {
        "some in \(name)"
    }

    func getLocationByUUID(UUID: String) -> String {
        "0.0, 0.0 -> \(UUID)"
    }
}
