import Foundation

actor WebSessionManager {
    private let authService: WebRemoteAuthService
    private var authenticatedConnections: Set<String> = []
    private var allConnections: Set<String> = []
    private var connectionAddresses: [String: String] = [:]
    private var authTimeouts: [String: Task<Void, Never>] = [:]
    private static let authTimeoutSeconds: UInt64 = 30

    /// Called when an unauthenticated connection should be forcibly closed.
    var onDisconnect: (@Sendable (String) -> Void)?

    /// Called for authenticated, non-auth messages. Returns response to send back.
    var onAuthenticatedMessage: (@Sendable (String, WebClientMessage) async -> WebServerMessage)?

    init(authService: WebRemoteAuthService) {
        self.authService = authService
    }

    func handleConnect(id: String, remoteAddress: String) {
        allConnections.insert(id)
        connectionAddresses[id] = remoteAddress
        // Start auth timeout — disconnect if not authenticated within limit
        authTimeouts[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.authTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.evictIfUnauthenticated(id)
        }
    }

    func handleDisconnect(id: String) {
        allConnections.remove(id)
        authenticatedConnections.remove(id)
        connectionAddresses.removeValue(forKey: id)
        authTimeouts[id]?.cancel()
        authTimeouts.removeValue(forKey: id)
    }

    private func isAuthenticated(_ id: String) -> Bool {
        authenticatedConnections.contains(id)
    }

    private func evictIfUnauthenticated(_ id: String) {
        guard !authenticatedConnections.contains(id) else { return }
        NSLog("[WebSessionManager] auth timeout for \(id), disconnecting")
        handleDisconnect(id: id)
        onDisconnect?(id)
    }

    /// Process incoming WebSocket data. Returns response Data to send back, or nil if unhandled.
    func handleMessage(data: Data, from connectionID: String) async -> Data? {
        guard allConnections.contains(connectionID) else { return nil }

        guard let message = try? JSONDecoder().decode(WebClientMessage.self, from: data) else {
            let errorMsg = WebServerMessage.error("Invalid message format")
            return try? JSONEncoder().encode(errorMsg)
        }

        // Auth messages are always accepted
        if message.type == .auth {
            let response = await processAuth(message, connectionID: connectionID)
            return try? JSONEncoder().encode(response)
        }

        // Ping is always accepted (even unauthenticated)
        if message.type == .ping {
            let response = WebServerMessage.pong(requestID: message.requestID)
            return try? JSONEncoder().encode(response)
        }

        // All other messages require authentication
        guard authenticatedConnections.contains(connectionID) else {
            let response = WebServerMessage.error("Not authenticated", requestID: message.requestID)
            return try? JSONEncoder().encode(response)
        }

        // Delegate to coordinator
        if let handler = onAuthenticatedMessage {
            let response = await handler(connectionID, message)
            return try? JSONEncoder().encode(response)
        }

        let response = WebServerMessage.error("No handler configured", requestID: message.requestID)
        return try? JSONEncoder().encode(response)
    }

    func authenticatedConnectionCount() -> Int {
        authenticatedConnections.count
    }

    func authenticatedConnectionIDs() -> Set<String> {
        authenticatedConnections
    }

    func revokeAllAuthenticated() {
        authenticatedConnections.removeAll()
    }

    func totalConnectionCount() -> Int {
        allConnections.count
    }

    func setOnAuthenticatedMessage(_ handler: @escaping @Sendable (String, WebClientMessage) async -> WebServerMessage) {
        self.onAuthenticatedMessage = handler
    }

    func setOnDisconnect(_ handler: @escaping @Sendable (String) -> Void) {
        self.onDisconnect = handler
    }

    // MARK: - Private

    private func processAuth(_ message: WebClientMessage, connectionID: String) async -> WebServerMessage {
        guard let candidateToken = message.token, !candidateToken.isEmpty else {
            return WebServerMessage.authFailure("Token required")
        }

        let remoteAddress = connectionAddresses[connectionID] ?? "unknown"
        let valid = await authService.validate(candidateToken: candidateToken, remoteAddress: remoteAddress)

        if valid {
            authenticatedConnections.insert(connectionID)
            authTimeouts[connectionID]?.cancel()
            authTimeouts.removeValue(forKey: connectionID)
            return WebServerMessage.authSuccess(token: candidateToken)
        } else {
            let banned = await authService.isIPBanned(remoteAddress)
            if banned {
                return WebServerMessage.authFailure("IP banned due to too many failed attempts")
            }
            return WebServerMessage.authFailure("Invalid token")
        }
    }
}
