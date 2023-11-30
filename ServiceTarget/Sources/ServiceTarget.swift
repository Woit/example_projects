// Simple HTTP ping server
//
import ArgumentParser
import Foundation
import NIO
import NIOHTTP1

@main
struct ServiceTarget: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A simple HTTP server which is responding 'ok' wiht random delay",
        subcommands: [Start.self]
    )
}

struct Start: ParsableCommand {
    @Argument(help: "Server start")
    private var port: Int = 8080

    static let configuration = CommandConfiguration(abstract: "Start server with specific port")

    mutating func run() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        defer {
            try? group.syncShutdownGracefully()
        }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap { channel.pipeline.addHandler(HTTPHandler()) }
            }

        let channel = try bootstrap.bind(host: "localhost", port: port)
            .wait()

        print("Server started and listening on port \(port)")
        try channel.closeFuture.wait()
        print("Server closed")
    }
}

let msec20: UInt32 = 20000 // 20 ms
let sec5: UInt32 = 5_000_000 // 5 sec

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)

        switch request {
        case let .head(header):
            let channel = context.channel

            let head: HTTPResponseHead
            var buffer: NIOCore.ByteBuffer

            if header.method == .GET, header.uri == "/ping" {
                head = HTTPResponseHead(version: header.version, status: .ok)
                buffer = channel.allocator.buffer(capacity: 4)
                buffer.writeString("ok")
                usleep(UInt32.random(in: msec20 ... sec5))
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

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}
