import ArgumentParser
import Foundation
import swift_polis

@main
struct AstroSearch: ParsableCommand {
    mutating func run() throws {
        print("Service started")

        RemoteDownloader("http: // test.polis.observer/polis").downloadIfNeeded {
            print("Data downloaded")
        }
    }
}

struct RemoteDownloader {
    let polisRemotePath: String

    init(_ remotePath: String) {
        polisRemotePath = remotePath
    }

    func downloadIfNeeded(atReady: @escaping () -> Void) {
        if !Utils.directoryExistsAtPath("./polis") {
            print("Start async downloading")
            DispatchQueue.global().async {
                _ = Utils.shell("wget -r -q -np -nH -A json \(polisRemotePath) ")
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
}
