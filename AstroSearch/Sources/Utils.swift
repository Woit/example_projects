// Utils
import Foundation

/// Utility for downloading files from remote source.
/// This utility uses system tool 'wget' for recursivelly download files and folders from remote folder
struct RemoteDownloader {
    /// Remote source url
    let polisRemotePath: String
    /// Local storage folder path
    let polisLocalPath: String

    /// Init downloading tool.
    /// - Parameters:
    ///    - fromRemote: Remote source url
    ///    - toLocal: Local storage folder
    /// - Returns: Downloader
    init(fromRemote: String, toLocal: String) {
        polisRemotePath = fromRemote
        polisLocalPath = toLocal
    }

    /// Downloading method. This method will download data to local folder if that folder not yet exists.
    /// Otherwise will do nothing
    ///  - Parameters:
    ///    - atReady: Callback which will be invoke after downloading data
    func downloadIfNeeded(atReady: @escaping () -> Void) {
        if !Utils.directoryExistsAtPath("\(polisLocalPath)/polis") {
            print("Start async downloading")
            DispatchQueue.global().async {
                _ = Utils.shell("wget -r -q -np -nH -A json -P \(polisLocalPath) \(polisRemotePath) ")
                atReady()
            }
        } else {
            atReady()
        }
    }
}

/// Set of utilities
enum Utils {
    /// Method for run system command in shell
    /// - Parameters:
    ///    - cmd: String which represent command for system bash interpreter
    /// - Returns: Result of command execution
    static func shell(_ cmd: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", String(format: "%@", cmd)]
        process.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading
        process.launch()
        return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
    }

    /// Method for checking that some folder exists in filesystem
    /// - Parameters:
    ///    - path: Path to folder
    static func directoryExistsAtPath(_ path: String) -> Bool {
        var isDirectory: ObjCBool = true
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Method for reading bytes from file
    /// - Parameters:
    ///    - localFilePath: Path to local file
    /// - Returns: Data that contains bytes readed from file
    /// - Throws: Method may throw error if reading from file failed. Often that means that file not found at given path
    static func dataFromFilePath(_ localFilePath: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: localFilePath))
    }

    /// Method for converting swift structures to json stirng representation
    /// - Parameters:
    ///    - input: Any structure which conforms 'Encodable' protocol
    /// - Returns: JSON string representation
    static func structToJsonStr<A: Encodable>(input: A) -> String? {
        guard let jsonData = try? JSONEncoder().encode(input), let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return nil
        }
        return jsonString
    }
}
