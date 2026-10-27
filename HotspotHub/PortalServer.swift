import Foundation
import Combine
import Darwin
import NIOCore
import NIOHTTP1
import NIOPosix

private final class HealthMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var startDate: Date?
    func started(_ date: Date?) { lock.lock(); startDate = date; lock.unlock() }
    func payload() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                "status": startDate == nil ? "Offline" : "Online",
                "uptimeSeconds": startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0]
    }
}

private final class PortalHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let root: URL
    private let metrics: HealthMetrics
    private let maximumRequestBytes = 1_048_576
    private var request: HTTPRequestHead?
    private var receivedBytes = 0

    init(root: URL, metrics: HealthMetrics) { self.root = root; self.metrics = metrics }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            request = head; receivedBytes = 0
            if let length = head.headers.first(name: "content-length").flatMap(Int.init), length > maximumRequestBytes {
                respond(context, request: head, status: .payloadTooLarge, body: Data("Request too large".utf8))
                context.close(promise: nil)
            }
        case .body(let buffer):
            receivedBytes += buffer.readableBytes
            if receivedBytes > maximumRequestBytes {
                if let request { respond(context, request: request, status: .payloadTooLarge, body: Data("Request too large".utf8)) }
                context.close(promise: nil)
            }
        case .end:
            guard let head = request else { return }
            request = nil
            guard receivedBytes <= maximumRequestBytes else { return }
            route(head, context: context)
        }
    }

    private func route(_ request: HTTPRequestHead, context: ChannelHandlerContext) {
        guard request.method == .GET || request.method == .HEAD else {
            respond(context, request: request, status: .methodNotAllowed, body: Data("Method not allowed".utf8)); return
        }
        let rawPath = URLComponents(string: request.uri)?.percentEncodedPath.removingPercentEncoding ?? ""
        guard !rawPath.contains("\\"), !rawPath.split(separator: "/").contains("..") else {
            respond(context, request: request, status: .badRequest, body: Data("Invalid path".utf8)); return
        }
        if rawPath == "/health" {
            let body = (try? JSONSerialization.data(withJSONObject: metrics.payload(), options: [.sortedKeys])) ?? Data("{}".utf8)
            respond(context, request: request, status: .ok, body: body, contentType: "application/json; charset=utf-8"); return
        }
        let relative = rawPath == "/" ? "index.html" : String(rawPath.drop(while: { $0 == "/" }))
        let file = root.appendingPathComponent(relative).standardizedFileURL
        let rootPrefix = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        guard file.path.hasPrefix(rootPrefix), let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
              let size = values.fileSize, size <= 25 * 1024 * 1024, let body = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            respond(context, request: request, status: .notFound, body: Data("Not found".utf8)); return
        }
        respond(context, request: request, status: .ok, body: body, contentType: mimeType(file.pathExtension))
    }

    private func respond(_ context: ChannelHandlerContext, request: HTTPRequestHead, status: HTTPResponseStatus, body: Data, contentType: String = "text/plain; charset=utf-8") {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: String(body.count))
        headers.add(name: "X-Content-Type-Options", value: "nosniff")
        headers.add(name: "Cache-Control", value: "no-store")
        headers.add(name: "Connection", value: request.isKeepAlive ? "keep-alive" : "close")
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: request.version, status: status, headers: headers))), promise: nil)
        if request.method != .HEAD && !body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        if !request.isKeepAlive { context.close(promise: nil) }
    }

    private func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "ico": "image/x-icon"
        default: "application/octet-stream"
        }
    }
}

private final class IdleConnectionHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    typealias OutboundOut = NIOAny
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let idle = event as? IdleStateHandler.IdleStateEvent, idle == .read {
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

@MainActor
final class PortalServer: ObservableObject {
    @Published private(set) var state = "Offline"
    @Published private(set) var address: String?
    @Published private(set) var error: String?
    private let metrics = HealthMetrics()
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var startID = 0
    private let port = 8080

    func start() {
        guard channel == nil, group == nil, state != "Starting" else { return }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("WebPortal", isDirectory: true),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            state = "Error"; error = "Portal assets are missing from the app bundle."; return
        }
        guard let bindAddress = localIPv4() else {
            state = "Error"; error = "No active local IPv4 address was found. Enable Personal Hotspot or connect to Wi-Fi, then try again."; return
        }
        state = "Starting"; error = nil
        startID += 1
        let attemptID = startID
        let metrics = self.metrics
        let port = self.port
        Task.detached { [weak self] in
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            do {
                let server = try ServerBootstrap(group: eventLoopGroup)
                    .serverChannelOption(ChannelOptions.backlog, value: 128)
                    .childChannelInitializer { channel in
                        channel.pipeline.configureHTTPServerPipeline().flatMap {
                            channel.pipeline.addHandler(IdleStateHandler(readTimeout: .seconds(30))).flatMap {
                                channel.pipeline.addHandler(IdleConnectionHandler()).flatMap {
                                    channel.pipeline.addHandler(PortalHTTPHandler(root: root, metrics: metrics))
                                }
                            }
                        }
                    }
                    .bind(host: bindAddress, port: port).wait()
                await MainActor.run {
                    guard let self, self.state == "Starting", self.startID == attemptID else {
                        try? server.close().wait()
                        try? eventLoopGroup.syncShutdownGracefully()
                        return
                    }
                    self.group = eventLoopGroup; self.channel = server
                    self.metrics.started(Date()); self.state = "Online"
                    self.address = "http://\(bindAddress):\(self.port)/"
                }
            } catch {
                try? eventLoopGroup.syncShutdownGracefully()
                await MainActor.run {
                    guard let self, self.state == "Starting", self.startID == attemptID else { return }
                    self.state = "Error"; self.error = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        startID += 1
        state = "Stopping"; metrics.started(nil); address = nil
        let oldChannel = channel; let oldGroup = group
        channel = nil; group = nil
        if let oldChannel { try? oldChannel.close().wait() }
        if let oldGroup { try? oldGroup.syncShutdownGracefully() }
        state = "Offline"
    }

    private func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            let info = current.pointee
            if let addr = info.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               let name = String(validatingUTF8: info.ifa_name), name != "lo0",
               let numeric = sockaddrIPv4(addr) { return numeric }
            item = info.ifa_next
        }
        return nil
    }

    private func sockaddrIPv4(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }
}
