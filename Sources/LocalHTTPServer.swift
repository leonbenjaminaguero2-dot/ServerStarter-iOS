import Foundation
import Network

/// Servidor HTTP/1.1 limitado al dispositivo: 127.0.0.1:8080.
/// El acceso al listener y a las conexiones se serializa en `queue`.
final class LocalHTTPServer {
    enum Status {
        case starting
        case running
        case stopped
        case failed(String)
    }

    var onStatus: ((Status) -> Void)?
    var onRequest: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.nexora.serverstarter.http", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let port = NWEndpoint.Port(rawValue: 8080)!
    private let maximumHeaderBytes = 32_768
    private let maximumConcurrentConnections = 32

    func start(directory root: URL) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cancelCurrentServer()
            let index = root.appendingPathComponent("index.html")
            guard FileManager.default.fileExists(atPath: index.path) else {
                self.onStatus?(.failed("Falta index.html. Elegí un archivo HTML."))
                return
            }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: self.port)
                let current = try NWListener(using: parameters, on: self.port)
                self.listener = current
                self.onStatus?(.starting)
                current.stateUpdateHandler = { [weak self, weak current] state in
                    guard let self = self, let current = current,
                          self.listener === current else { return }
                    switch state {
                    case .ready:
                        self.onStatus?(.running)
                    case .failed(let error):
                        self.cancelCurrentServer()
                        self.onStatus?(.failed("No se pudo iniciar el puerto 8080: \(error.localizedDescription)"))
                    default:
                        break
                    }
                }
                current.newConnectionHandler = { [weak self, weak current] connection in
                    guard let self = self, let current = current,
                          self.listener === current else { connection.cancel(); return }
                    self.accept(connection, root: root)
                }
                current.start(queue: self.queue)
            } catch {
                self.onStatus?(.failed("No se pudo iniciar localhost: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cancelCurrentServer()
            self.onStatus?(.stopped)
        }
    }

    private func cancelCurrentServer() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection, root: URL) {
        guard connections.count < maximumConcurrentConnections else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        readRequest(connection, id: id, root: root, collected: Data())
    }

    private func readRequest(_ connection: NWConnection, id: UUID, root: URL, collected: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, completed, error in
            guard let self = self, self.connections[id] != nil else { connection.cancel(); return }
            var request = collected
            if let chunk = chunk { request.append(chunk) }
            if request.count > self.maximumHeaderBytes {
                self.send(connection, id: id, code: 431, reason: "Request Header Fields Too Large",
                          body: Data(), contentType: "text/plain", headOnly: false)
            } else if request.range(of: Data([13, 10, 13, 10])) != nil {
                self.respond(connection, id: id, request: request, root: root)
            } else if completed || error != nil {
                self.close(connection, id: id)
            } else {
                self.readRequest(connection, id: id, root: root, collected: request)
            }
        }
    }

    private func respond(_ connection: NWConnection, id: UUID, request: Data, root: URL) {
        guard let line = String(data: request, encoding: .utf8)?.components(separatedBy: "\r\n").first else {
            sendError(connection, id: id, code: 400, reason: "Bad Request")
            return
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { sendError(connection, id: id, code: 400, reason: "Bad Request"); return }
        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            sendError(connection, id: id, code: 405, reason: "Method Not Allowed"); return
        }
        let rawPath = String(parts[1].prefix { $0 != "?" && $0 != "#" })
        guard rawPath.hasPrefix("/"), let decoded = rawPath.removingPercentEncoding,
              !decoded.contains("\0"), !decoded.contains("\\") else {
            sendError(connection, id: id, code: 400, reason: "Bad Request"); return
        }
        let segments = decoded.split(separator: "/").map(String.init)
        guard !segments.contains(".."), !segments.contains(".") else {
            sendError(connection, id: id, code: 403, reason: "Forbidden"); return
        }
        let relative = segments.isEmpty ? "index.html" : segments.joined(separator: "/")
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var file = canonicalRoot.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            file = file.appendingPathComponent("index.html")
        }
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard file.path.hasPrefix(rootPrefix) else {
            sendError(connection, id: id, code: 403, reason: "Forbidden"); return
        }
        guard let body = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            sendError(connection, id: id, code: 404, reason: "Not Found"); return
        }
        onRequest?("\(method) /\(relative) · 200")
        send(connection, id: id, code: 200, reason: "OK", body: body,
             contentType: mimeType(for: file), headOnly: method == "HEAD")
    }

    private func sendError(_ connection: NWConnection, id: UUID, code: Int, reason: String) {
        onRequest?("HTTP \(code) · \(reason)")
        send(connection, id: id, code: code, reason: reason,
             body: Data("\(code) \(reason)".utf8),
             contentType: "text/plain; charset=utf-8", headOnly: false)
    }

    private func send(_ connection: NWConnection, id: UUID, code: Int, reason: String,
                      body: Data, contentType: String, headOnly: Bool) {
        let header = "HTTP/1.1 \(code) \(reason)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "Cache-Control: no-store\r\n" +
            "X-Content-Type-Options: nosniff\r\n\r\n"
        var packet = Data(header.utf8)
        if !headOnly { packet.append(body) }
        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            self?.close(connection, id: id)
        })
    }

    private func close(_ connection: NWConnection, id: UUID) {
        connections.removeValue(forKey: id)
        connection.cancel()
    }

    private func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "htm", "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "pdf": return "application/pdf"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
