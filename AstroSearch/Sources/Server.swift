import Foundation
import NIO
import NIOHTTP1

enum ServerState {
    case notReady
    case ready
}

enum ServerError {
    case forbidden
    case parameterRequired(String)
    case notReady
}

// - `updateDate` - returns the last update date of the data set
// - `numberOfObservingFacilities` - returns the number of facilities in the current data set
// - `search?name=xxx` - returns the UUIDs of all facilities with a name containing the search criteria.
// - `location?uuid=UUID` - returns the longitude and latitude (as Double values) of a facility with a given UUID.
enum Api: CaseIterable {
    case updateDate
    case numberOfObservingFacilities
    case search(String)
    case location(String)

    var uri: String {
        switch self {
        case .updateDate: return "/api/updateDate"
        case .numberOfObservingFacilities: return "/api/numberOfObservingFacilities"
        case .search: return "/api/search"
        case .location: return "/api/location"
        }
    }

    static var allCases: [Api] {
        [.updateDate, .numberOfObservingFacilities, .search(""), .location("")]
    }
}

final class Server {
    let port: Int
    let dataPath: String
    var handler = HTTPHandler()
    var state: ServerState = .notReady {
        didSet {
            handler.state = state
            print("state updated \(state)")
        }
    }

    init(port: Int, dataPath: String) {
        self.port = port
        self.dataPath = dataPath
    }

    func run() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        defer {
            try? group.syncShutdownGracefully()
        }

        let handler = handler
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap { channel.pipeline.addHandler(handler) }
            }

        let channel = try bootstrap.bind(host: "localhost", port: port)
            .wait()

        print("Server started and listening at localhost:\(port)/api")
        try channel.closeFuture.wait()
        print("Server closed")
    }
}

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    var state: ServerState = .notReady

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channel = context.channel
        if state != .ready {
            serverError(channel: channel, reason: .notReady)
        }

        let request = unwrapInboundIn(data)
        switch request {
        case let .head(header):
            print(header.uri)
            guard header.method == .GET else {
                serverError(channel: channel, reason: .forbidden)
                return
            }

            guard Api.allCases.map({ $0.uri }).contains(header.uri) else {
                serverError(channel: channel, reason: .forbidden)
                return
            }

            let head: HTTPResponseHead
            var buffer: NIOCore.ByteBuffer

            if header.method == .GET, header.uri == "api" {
                head = HTTPResponseHead(version: header.version, status: .ok)
                buffer = channel.allocator.buffer(capacity: 4)
                buffer.writeString("OK")
            } else {
                head = HTTPResponseHead(version: header.version, status: .forbidden)
                buffer = channel.allocator.buffer(capacity: 18)
                buffer.writeString("Forbidden")
            }

            let part = HTTPServerResponsePart.head(head)
            _ = channel.write(part)

            let bodypart = HTTPServerResponsePart.body(.byteBuffer(buffer))
            _ = channel.write(bodypart)

            let endpart = HTTPServerResponsePart.end(nil)
            _ = channel.writeAndFlush(endpart).flatMap {
                channel.close()
            }

        case .body, .end:
            break
        }
    }

    func serverError(channel: Channel, reason: ServerError) {
        var head: HTTPResponseHead
        var buffer: NIOCore.ByteBuffer
        switch reason {
        case .forbidden:
            head = HTTPResponseHead(version: .http1_1, status: .forbidden)
            buffer = channel.allocator.buffer(capacity: 18)
            buffer.writeString("Forbidden")

        case let .parameterRequired(parameter):
            head = HTTPResponseHead(version: .http1_1, status: .badRequest)
            let msg = "Missing parameter: \(parameter)"
            buffer = channel.allocator.buffer(capacity: msg.count * 2)
            buffer.writeString(msg)

        case .notReady:
            head = HTTPResponseHead(version: .http1_1, status: .ok)
            buffer = channel.allocator.buffer(capacity: 84)
            buffer.writeString("Service not yet ready (data downloading...)")
        }
        let part = HTTPServerResponsePart.head(head)
        _ = channel.write(part)

        let bodypart = HTTPServerResponsePart.body(.byteBuffer(buffer))
        _ = channel.write(bodypart)

        let endpart = HTTPServerResponsePart.end(nil)
        _ = channel.writeAndFlush(endpart).flatMap {
            channel.close()
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}
