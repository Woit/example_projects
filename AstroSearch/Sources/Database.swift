import Foundation
import SoftwareEtudesUtilities
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

    private var polisResources: PolisFileResourceFinder?
    private var polisDirectory: PolisDirectory?
    private var polisFascilitiesDirectory: PolisObservingFacilityDirectory?

    init(remotePath: String, localPath: String) {
        self.remotePath = remotePath
        self.localPath = localPath
        loader = RemoteDownloader(fromRemote: remotePath, toLocal: localPath)
        loader.downloadIfNeeded { [weak self] in
            self?.setupData()
            self?.state = .ready
        }
    }

    func getLastUpdateTime() -> String {
        polisDirectory?.lastUpdate.formatted() ?? ""
    }

    func getNumFascilities() -> String {
        "\(polisFascilitiesDirectory?.observingFacilityReferences.count ?? 0)"
    }

    func getByName(name: String) -> String {
        if let item = polisFascilitiesDirectory?.observingFacilityReferences.first(where: { $0.identity.name == name }) {
            return item.identity.id.uuidString
        } else {
            return "empty"
        }
    }

    func getLocationByUUID(UUID: String) -> String {
        "0.0, 0.0 -> \(UUID)"
    }

    private func setupData() {
        guard let ver = SemanticVersion(with: "0.2.0-alpha.1") else { return }
        polisResources = try? PolisFileResourceFinder(
            at: URL(filePath: localPath),
            supportedImplementation: .init(
                dataFormat: PolisImplementation.DataFormat.json,
                apiSupport: PolisImplementation.APILevel.staticData,
                version: ver
            )
        )

        guard let polisResources else { return }
        let jsonDecoder = PolisJSONDecoder()

        if let data = try? Utils.dataFromFilePath(polisResources.polisProviderDirectoryFile()) {
            polisDirectory = try? jsonDecoder.decode(PolisDirectory.self, from: data)
        }

        if let data = try? Utils.dataFromFilePath(polisResources.observingFacilitiesDirectoryFile()) {
            polisFascilitiesDirectory = try? jsonDecoder.decode(PolisObservingFacilityDirectory.self, from: data)
        }
    }
}
