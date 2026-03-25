import Foundation
import Network

// MARK: - Delegate Protocol

protocol WebSocketServerDelegate: AnyObject, Sendable {
    func webSocketDidAcceptConnection(id: String, remoteAddress: String)
    func webSocketDidReceiveMessage(data: Data, from connectionID: String)
    func webSocketDidCloseConnection(id: String)
}

// MARK: - WebSocket Server (NWListener + NWProtocolWebSocket)

final class WebSocketServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let maxConnections: Int
    private var connections: [String: NWConnection] = [:]
    weak var delegate: WebSocketServerDelegate?

    var activeConnectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }

    private static let defaultMaxConnections = 20

    init(port: UInt16, loopbackOnly: Bool = true, maxConnections: Int = defaultMaxConnections) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AppError.invalidData("Invalid WebSocket port: \(port)")
        }

        let tcpOptions = NWProtocolTCP.Options()
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1_048_576 // 1 MB per message

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        if loopbackOnly {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            self.listener = try NWListener(using: parameters)
        } else {
            self.listener = try NWListener(using: parameters, on: nwPort)
        }
        self.queue = DispatchQueue(label: "aimenu.web-remote.ws", qos: .userInitiated)
        self.maxConnections = maxConnections
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                NSLog("[WebSocketServer] listener failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    /// Start and wait for the listener to become ready (or fail).
    func startAndWaitReady(timeout: TimeInterval = 5) async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        let readinessGate = ReadinessGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    readinessGate.resume(continuation, with: .success(()))
                case .failed(let error):
                    readinessGate.resume(continuation, with: .failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                readinessGate.resume(continuation, with: .failure(AppError.network("WebSocket server failed to start within \(Int(timeout))s")))
            }
        }
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let current = connections
        connections.removeAll()
        lock.unlock()
        for (_, conn) in current {
            conn.cancel()
        }
    }

    func send(data: Data, to connectionID: String) {
        lock.lock()
        let conn = connections[connectionID]
        lock.unlock()
        guard let conn else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws-text", metadata: [metadata])
        conn.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error {
                NSLog("[WebSocketServer] send error to \(connectionID): \(error.localizedDescription)")
            }
        })
    }

    func broadcast(data: Data, to connectionIDs: Set<String>) {
        for id in connectionIDs {
            send(data: data, to: id)
        }
    }

    func disconnect(_ connectionID: String) {
        lock.lock()
        let conn = connections.removeValue(forKey: connectionID)
        lock.unlock()
        conn?.cancel()
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = UUID().uuidString
        let remoteAddress = Self.remoteAddress(from: connection.endpoint)

        lock.lock()
        let currentCount = connections.count
        if currentCount >= maxConnections {
            lock.unlock()
            NSLog("[WebSocketServer] connection rejected (limit \(maxConnections)): \(remoteAddress)")
            connection.cancel()
            return
        }
        connections[connectionID] = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("[WebSocketServer] connection ready: \(connectionID) from \(remoteAddress)")
                self?.delegate?.webSocketDidAcceptConnection(id: connectionID, remoteAddress: remoteAddress)
                self?.receiveLoop(connection, id: connectionID)
            case .failed(let error):
                NSLog("[WebSocketServer] connection failed: \(connectionID) - \(error.localizedDescription)")
                self?.removeConnection(connectionID)
            case .cancelled:
                self?.removeConnection(connectionID)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(_ connection: NWConnection, id connectionID: String) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("[WebSocketServer] receive error from \(connectionID): \(error.localizedDescription)")
                self.removeConnection(connectionID)
                return
            }

            // Process WebSocket frame if we have data
            if let data = content, !data.isEmpty {
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                    switch metadata.opcode {
                    case .close:
                        NSLog("[WebSocketServer] close frame from \(connectionID)")
                        self.removeConnection(connectionID)
                        return
                    case .text, .binary:
                        self.delegate?.webSocketDidReceiveMessage(data: data, from: connectionID)
                    default:
                        break
                    }
                } else {
                    // No WebSocket metadata but has data — treat as text
                    self.delegate?.webSocketDidReceiveMessage(data: data, from: connectionID)
                }
            } else if content == nil && isComplete {
                // No data + isComplete = connection ended
                NSLog("[WebSocketServer] connection ended: \(connectionID)")
                self.removeConnection(connectionID)
                return
            }

            // Continue receiving next frame
            self.receiveLoop(connection, id: connectionID)
        }
    }

    private func removeConnection(_ connectionID: String) {
        lock.lock()
        let conn = connections.removeValue(forKey: connectionID)
        lock.unlock()
        conn?.cancel()
        delegate?.webSocketDidCloseConnection(id: connectionID)
    }

    private static func remoteAddress(from endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            return host.debugDescription
        default:
            return endpoint.debugDescription
        }
    }
}

// MARK: - Readiness Gate (thread-safe one-shot continuation wrapper)

/// Ensures a `CheckedContinuation` is resumed exactly once from any thread.
private final class ReadinessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        resumed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}
