import Foundation
import SoftwareEtudesUtilities
import swift_polis

/// Database  states influence that how server will operate
enum DatabaseState {
    /// notReady state will apply while service donwloading remote data
    case notReady
    /// ready means that service ready for acces
    case ready
    /// initError - this state will apply if some errors will appears during database initialization process
    case initError(String)
}

/// Database errors indicates places and types of errors which happens during Polis data accessing
enum DatabaseError: String, Error {
    /// This error appears during init Polis version
    case version = "Init Polis version failed"
    /// Means that service can't init class which is operate with data folder (probably something wrong with paths)
    case polisFolder = "Init PolisFileResourceFinder failed"
    /// Means Polis Directory wasn't initiated (probably JSON decoding error)
    case polisDirectory = "Parse PolisDirectory failed"
    /// Means that Facilities Directory wasn't initiated (probably JSON decoding error)
    case polisFacilitiesDirectory = "Parse PolisFacilitiesDirectory failed"
    /// Means that Facility wasn't initiated (probably JSON decoding error, or neede JSON file wasn't found in data directory)
    case polisFacility = "Parse PolisFacility failed"
    /// Means that some result data can't be formatted as JSON-string
    case dataEncodingError
}

/// Class provides access to data from api methods
final class DataBase {
    private(set) var state: DatabaseState = .notReady
    private let remotePath: String
    private let localPath: String
    private let loader: RemoteDownloader

    private var polisResources: PolisFileResourceFinder?
    private var polisDirectory: PolisDirectory?
    private var polisFacilitiesDirectory: PolisObservingFacilityDirectory?

    /// Database initialization
    /// - Parameters:
    ///   - remotePath: Polis data source url
    ///   - localPath: Path where Polis data will be stored locally
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

    /// Method for getting last update timestamp
    /// - Returns: JSON string which contains timestamp
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

    /// Method for getting total number of facilities
    /// - Returns: JSON string which contains number of fafcilities
    func getNumFacilities() throws -> String {
        guard
            let num = polisFacilitiesDirectory?.observingFacilityReferences.count,
            let result = Utils.structToJsonStr(input: ["number_of_fascilities": num])
        else {
            throw DatabaseError.dataEncodingError
        }
        return result
    }

    /// Method for getting UUID's of facilities with given part of name
    /// - Parameters:
    ///    - name: Name or part of name (will be searching by substring) of facility
    /// - Returns: JSON string which represent array of founded UUID's
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

    /// Method for getting latitude/longitude for given facility
    /// - Parameters:
    ///   - UUID: UUID for given facility
    /// - Returns: JSON string which contains latitude/longitude values
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

    // Internal init method
    private func setupData() throws {
        // Init semantic version and resource finder
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

        // Init Polis JSON decoder and bind Polis resource finder locally
        let jsonDecoder = PolisJSONDecoder()
        guard let polisResources = polisResources else {
            throw DatabaseError.polisFolder
        }

        // Init Polis directory
        do {
            let data = try Utils.dataFromFilePath(polisResources.polisProviderDirectoryFile())
            polisDirectory = try jsonDecoder.decode(PolisDirectory.self, from: data)
        } catch {
            throw DatabaseError.polisDirectory
        }

        // Init Polis facility directory
        do {
            let data = try Utils.dataFromFilePath(polisResources.observingFacilitiesDirectoryFile())
            polisFacilitiesDirectory = try jsonDecoder.decode(PolisObservingFacilityDirectory.self, from: data)
        } catch {
            throw DatabaseError.polisFacilitiesDirectory
        }
    }

    // Getting facility object from local file
    private func getFacilityByUUID(_ uuid: String) throws -> PolisObservingFacility {
        let jsonDecoder = PolisJSONDecoder()
        guard let polisResources = polisResources else {
            throw DatabaseError.polisFolder
        }
        let path = polisResources.observingFacilityFile(observingFacilityID: uuid)
        let facility = try jsonDecoder.decode(PolisObservingFacility.self, from: Utils.dataFromFilePath(path))
        return facility
    }

    // Getting location object from local file
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
