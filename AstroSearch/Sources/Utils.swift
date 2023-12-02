// Utils
import Foundation

struct RemoteDownloader {
    let polisRemotePath: String
    let polisLocalPath: String

    init(fromRemote: String, toLocal: String) {
        polisRemotePath = fromRemote
        polisLocalPath = toLocal
    }

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

enum Utils {
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

    static func directoryExistsAtPath(_ path: String) -> Bool {
        var isDirectory: ObjCBool = true
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func dataFromFilePath(_ localFilePath: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: localFilePath))
    }
}
