import Foundation
import NIO
import NIOHTTP1

enum ServerError {
    case forbidden
    case parameterRequired(String)
    case notReady
    case internalError
}

// - `updateDate` - returns the last update date of the data set
// - `numberOfObservingFacilities` - returns the number of facilities in the current data set
// - `search?name=xxx` - returns the UUIDs of all facilities with a name containing the search criteria.
// - `location?uuid=UUID` - returns the longitude and latitude (as Double values) of a facility with a given UUID.
private enum Api: String, CaseIterable, Codable {
    case updateDate = "/api/updateDate"
    case numberOfObservingFacilities = "/api/numberOfObservingFacilities"
    case search = "/api/search"
    case location = "/api/location"
}

final class Server {
    let port: Int
    let database: DataBase
    private var httpHandler: HTTPHandler

    init(port: Int, database: DataBase) {
        self.port = port
        self.database = database
        httpHandler = HTTPHandler(database: database)
    }

    func run() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        defer {
            try? group.syncShutdownGracefully()
        }

        let httpHandler = httpHandler
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap { channel.pipeline.addHandler(httpHandler) }
            }

        let channel = try bootstrap.bind(host: "localhost", port: port)
            .wait()

        print("Server started and listening at localhost:\(port)/api")
        try channel.closeFuture.wait()
        print("Server closed")
    }
}

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    weak var database: DataBase?

    init(database: DataBase) {
        self.database = database
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channel = context.channel
        guard let db = database else {
            serverError(channel: channel, reason: .internalError)
            return
        }
        if db.state != .ready {
            serverError(channel: channel, reason: .notReady)
            return
        }

        let request = unwrapInboundIn(data)
        switch request {
        case let .head(header):
            guard header.method == .GET else {
                serverError(channel: channel, reason: .forbidden)
                return
            }
            guard let components = URLComponents(string: header.uri) else {
                serverError(channel: channel, reason: .internalError)
                return
            }
            guard let api = Api(rawValue: components.path) else {
                serverError(channel: channel, reason: .forbidden)
                return
            }

            let params = components.percentEncodedQueryItems?
                .compactMap { $0.value != nil ? $0 : nil }
                .reduce([String: String]()) { dict, item -> [String: String] in
                    var dict = dict
                    dict[item.name] = (item.value ?? "").removingPercentEncoding
                    return dict
                }

            var buffer: NIOCore.ByteBuffer
            switch api {
            case .updateDate:
                let msg = db.getLastUpdateTime()
                buffer = channel.allocator.buffer(capacity: msg.count * 2)
                buffer.writeString(msg)

            case .numberOfObservingFacilities:
                let msg = db.getNumFascilities()
                buffer = channel.allocator.buffer(capacity: msg.count * 2)
                buffer.writeString(msg)

            case .search:
                guard let params, let name = params["name"] else {
                    serverError(channel: channel, reason: .parameterRequired("name"))
                    return
                }
                let msg = db.getByName(name: name)
                buffer = channel.allocator.buffer(capacity: msg.count * 2)
                buffer.writeString(msg)

            case .location:
                guard let params, let uuid = params["uuid"] else {
                    serverError(channel: channel, reason: .parameterRequired("uuid"))
                    return
                }
                let msg = db.getLocationByUUID(UUID: uuid)
                buffer = channel.allocator.buffer(capacity: msg.count * 2)
                buffer.writeString(msg)
            }

            let head = HTTPResponseHead(version: .http1_1, status: .ok)
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

        case .internalError:
            head = HTTPResponseHead(version: .http1_1, status: .internalServerError)
            buffer = channel.allocator.buffer(capacity: 28)
            buffer.writeString("Internal error")
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

private struct APIRequest: Codable {
    let api: Api
    let params: [String: String]?
}
