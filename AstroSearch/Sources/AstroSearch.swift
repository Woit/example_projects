import ArgumentParser
import Foundation

let DEFAULT_PORT = 8080
let DEFAULT_DATA_PATH = "./polis"
let DEFAULT_REMOTE_SOURCE = "http://test.polis.observer/polis"

@main
struct AstroSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A simple HTTP server which provides some Polis data",
        subcommands: [Start.self]
    )
}

struct Start: ParsableCommand {
    @Argument(help: "Server start")
    private var port: Int = DEFAULT_PORT

    @Option(name: .shortAndLong, help: "Download data path")
    private var localPath: String = DEFAULT_DATA_PATH

    @Option(name: .shortAndLong, help: "Remote polis directory")
    private var remotePath: String = DEFAULT_REMOTE_SOURCE

    static let configuration = CommandConfiguration(abstract: "Start server with specific port")

    mutating func run() throws {
        let database = DataBase(remotePath: remotePath, localPath: localPath)
        let server = Server(port: port, database: database)
        try server.run()
    }
}
