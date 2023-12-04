import Foundation
import SoftwareEtudesUtilities
import swift_polis

enum DatabaseState {
    case notReady
    case ready
    case initError(String)
}

enum DatabaseError: String, Error {
    case version = "Init Polis version failed"
    case polisFolder = "Init PolisFileResourceFinder failed"
    case polisDirectory = "Parse PolisDirectory failed"
    case polisFacilitiesDirectory = "Parse PolisFacilitiesDirectory failed"
    case polisFacility = "Parse PolisFacility failed"
    case dataEncodingError
}

final class DataBase {
    private(set) var state: DatabaseState = .notReady
    private let remotePath: String
    private let localPath: String
    private let loader: RemoteDownloader

    private var polisResources: PolisFileResourceFinder?
    private var polisDirectory: PolisDirectory?
    private var polisFacilitiesDirectory: PolisObservingFacilityDirectory?

    init(remotePath: String, localPath: String) {
        self.remotePath = remotePath
        self.localPath = localPath
        loader = RemoteDownloader(fromRemote: remotePath, toLocal: localPath)
        loader.downloadIfNeeded { [weak self] in
            do {
                try self?.setupData()
                self?.state = .ready
            } catch let err as DatabaseError {
                self?.state = .initError(err.rawValue)
            } catch {
                self?.state = .initError("Unknown error")
            }
        }
    }

    func getLastUpdateTime() throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard
            let date = polisDirectory?.lastUpdate,
            let result = Utils.structToJsonStr(input: ["last_updated": formatter.string(from: date)])
        else {
            throw DatabaseError.dataEncodingError
        }
        return result
    }

    func getNumFacilities() throws -> String {
        guard
            let num = polisFacilitiesDirectory?.observingFacilityReferences.count,
            let result = Utils.structToJsonStr(input: ["number_of_fascilities": num])
        else {
            throw DatabaseError.dataEncodingError
        }
        return result
    }

    func getByName(name: String) throws -> String {
        let items = polisFacilitiesDirectory?.observingFacilityReferences
            .filter { $0.identity.name.lowercased().contains(name.lowercased()) }
            .map { $0.identity.id }

        if let res = Utils.structToJsonStr(input: items) {
            return res
        } else {
            throw DatabaseError.dataEncodingError
        }
    }

    func getLocationByUUID(UUID: String) throws -> String {
        let fascility = try getFacilityByUUID(UUID)
        guard
            let locationUUID = fascility.facilityLocationID,
            let location = try? getLocationByUUID(fascility.id.uuidString, locationUUID),
            let result = Utils.structToJsonStr(input: [
                "latitude": location.latitude?.value,
                "longitude": location.eastLongitude?.value
            ])
        else {
            throw DatabaseError.polisFacility
        }
        return result
    }

    private func setupData() throws {
        //
        guard let ver = SemanticVersion(with: "0.2.0-alpha.1") else {
            throw DatabaseError.version
        }
        do {
            polisResources = try PolisFileResourceFinder(
                at: URL(filePath: localPath),
                supportedImplementation: .init(
                    dataFormat: PolisImplementation.DataFormat.json,
                    apiSupport: PolisImplementation.APILevel.staticData,
                    version: ver
                )
            )
        } catch {
            throw DatabaseError.polisFolder
        }

        //
        let jsonDecoder = PolisJSONDecoder()
        guard let polisResources = polisResources else {
            throw DatabaseError.polisFolder
        }

        //
        do {
            let data = try Utils.dataFromFilePath(polisResources.polisProviderDirectoryFile())
            polisDirectory = try jsonDecoder.decode(PolisDirectory.self, from: data)
        } catch {
            throw DatabaseError.polisDirectory
        }

        //
        do {
            let data = try Utils.dataFromFilePath(polisResources.observingFacilitiesDirectoryFile())
            polisFacilitiesDirectory = try jsonDecoder.decode(PolisObservingFacilityDirectory.self, from: data)
        } catch {
            throw DatabaseError.polisFacilitiesDirectory
        }
    }

    private func getFacilityByUUID(_ uuid: String) throws -> PolisObservingFacility {
        let jsonDecoder = PolisJSONDecoder()
        guard let polisResources = polisResources else {
            throw DatabaseError.polisFolder
        }
        let path = polisResources.observingFacilityFile(observingFacilityID: uuid)
        let facility = try jsonDecoder.decode(PolisObservingFacility.self, from: Utils.dataFromFilePath(path))
        return facility
    }

    private func getLocationByUUID(_ uuid: String, _ locUUID: UUID) throws -> PolisObservingFacilityLocation {
        let jsonDecoder = PolisJSONDecoder()
        guard let polisResources = polisResources else {
            throw DatabaseError.polisFolder
        }
        let path = polisResources.observingDataFile(withID: locUUID, observingFacilityID: uuid)
        let location = try jsonDecoder.decode(PolisObservingFacilityLocation.self, from: Utils.dataFromFilePath(path))
        return location
    }
}
