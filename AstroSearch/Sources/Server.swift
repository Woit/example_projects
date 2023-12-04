import Foundation
import NIO
import NIOHTTP1

/// Server errors
enum ServerError {
    /// This error will return every time, when user tries to access to server path which is not exists
    case forbidden
    /// Error appears when request didn't contains needed parameters
    case parameterRequired(String)
    /// Error appears when service is not yet ready (in data downloading process)
    case notReady
    /// Wide error type which contains reason description
    case internalError(String?)
}

/// Server available api
private enum Api: String, CaseIterable, Codable {
    /// `/updateDate` - returns the last update date of the data set
    case updateDate = "/api/updateDate"
    /// `/numberOfObservingFacilities` - returns the number of facilities in the current data set
    case numberOfObservingFacilities = "/api/numberOfObservingFacilities"
    /// `/search?name=[some_symbols]` - returns the UUIDs of all facilities with a name containing the search criteria.
    case search = "/api/search"
    /// `location?uuid=[some_uuid]` - returns the longitude and latitude (as Double values) of a facility with a given UUID.
    case location = "/api/location"
}

/// Class implements server
final class Server {
    /// Server port
    let port: Int
    /// Database reference
    let database: DataBase
    private var httpHandler: HTTPHandler

    /// Method for getting UUID's of facilities with given part of name
    /// - Parameters:
    ///    - port: Port on whis server will operate
    ///    - database: Reference to Database object
    /// - Returns: Server instance
    init(port: Int, database: DataBase) {
        self.port = port
        self.database = database
        httpHandler = HTTPHandler(database: database)
    }

    /// Just run it!
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

// Main server handler
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
            serverError(channel: channel, reason: .internalError("Unknown error"))
            return
        }
        switch db.state {
        case .notReady:
            serverError(channel: channel, reason: .notReady)
            return

        case let .initError(reason):
            serverError(channel: channel, reason: .internalError(reason))

        case .ready:
            break
        }

        let request = unwrapInboundIn(data)
        switch request {
        case let .head(header):
            guard header.method == .GET else {
                serverError(channel: channel, reason: .forbidden)
                return
            }
            guard let components = URLComponents(string: header.uri) else {
                serverError(channel: channel, reason: .internalError("Request parsin error with \(header.uri)"))
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

            var msg = ""
            do {
                switch api {
                case .updateDate:
                    msg = try db.getLastUpdateTime()

                case .numberOfObservingFacilities:
                    msg = try db.getNumFacilities()

                case .search:
                    guard let params, let name = params["name"] else {
                        serverError(channel: channel, reason: .parameterRequired("name"))
                        return
                    }
                    msg = try db.getByName(name: name)

                case .location:
                    guard let params, let uuid = params["uuid"] else {
                        serverError(channel: channel, reason: .parameterRequired("uuid"))
                        return
                    }
                    msg = try db.getLocationByUUID(UUID: uuid)
                }
            } catch let err as DatabaseError {
                serverError(channel: channel, reason: .internalError(err.rawValue))
                return
            } catch {
                print(error)
                serverError(channel: channel, reason: .internalError(error.localizedDescription))
                return
            }

            var head = HTTPResponseHead(version: .http1_1, status: .ok)
            head.headers.add(name: "Content-Type", value: "application/json")

            let part = HTTPServerResponsePart.head(head)
            _ = channel.write(part)

            var buffer: NIOCore.ByteBuffer
            buffer = channel.allocator.buffer(capacity: msg.count * 2)
            buffer.writeString(msg)
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

        case let .internalError(msg):
            head = HTTPResponseHead(version: .http1_1, status: .internalServerError)
            buffer = channel.allocator.buffer(capacity: 28)
            let msg = msg ?? "Internal error"
            #if DEBUG
                buffer.writeString(msg)
            #else
                buffer.writeString("Unknown error")
            #endif
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
