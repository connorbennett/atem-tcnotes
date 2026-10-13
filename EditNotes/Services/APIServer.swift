import Foundation
import Network

/// Tiny read-only HTTP server the Companion module polls to discover the current shortcuts.
nonisolated final class APIServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "EditNotes.API")
    private var listener: NWListener?

    /// `body` produces the JSON for `GET /api/state`; `onFailure` reports a listener failure (e.g. port in use).
    func start(port: UInt16, body: @escaping @Sendable () async -> Data,
               onFailure: @escaping @Sendable (String) -> Void) throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error.localizedDescription) }
        }
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .split(separator: "\r\n").first.map(String.init) ?? ""
                let parts = requestLine.split(separator: " ")
                let path = parts.count > 1 ? parts[1].split(separator: "?").first.map(String.init) ?? "" : ""
                Task {
                    let response: Data
                    if parts.first == "GET", path == "/api/state" {
                        response = Self.response(status: "200 OK", body: await body())
                    } else {
                        response = Self.response(status: "404 Not Found", body: Data(#"{"error":"not found"}"#.utf8))
                    }
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        listener.start(queue: queue)
        queue.sync { self.listener = listener }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
        }
    }

    private static func response(status: String, body: Data) -> Data {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
