import Foundation

// MARK: - Client → Server

enum WebClientMessageType: String, Codable, Sendable {
    case auth
    case ping
    case requestAccounts
    case requestProviders
    case requestProxyStatus
    // Chat
    case sendMessage
    case createSession
    case listSessions
    case loadSession
    case deleteSession
    case abortSession
    // Provider CRUD
    case listAllProviders
    case addProvider
    case updateProvider
    case deleteProvider
    case switchProvider
    // Token
    case setToken
    // Directory & Commands
    case listDirectories
    case requestSlashCommands
    // Session management
    case renameSession
}

struct WebClientMessage: Codable, Sendable {
    var type: WebClientMessageType
    var token: String?
    var requestID: String?
    // Chat fields
    var text: String?
    var sessionID: String?
    var agent: String?
    var mode: String?
    var model: String?
    var cwd: String?
    // Provider fields
    var providerID: String?
    var providerName: String?
    var providerAppType: String?
    var providerApiKey: String?
    var providerBaseUrl: String?
    var providerModel: String?
    // Session fields
    var sessionTitle: String?
}

// MARK: - Server → Client

enum WebServerMessageType: String, Codable, Sendable {
    case authResult
    case pong
    case error
    case accountsSnapshot
    case providersSnapshot
    case proxyStatusSnapshot
    // Chat
    case sessionList
    case sessionDetail
    case textDelta
    case toolStart
    case toolEnd
    case chatDone
    case chatError
    // Provider CRUD
    case providerList
    case providerSaved
    case providerDeleted
    // Token
    case tokenUpdated
    // Directory & Commands
    case directoryList
    case slashCommands
    // Session management
    case sessionRenamed
    // Usage
    case usageUpdate
}

struct WebServerMessage: Codable, Sendable {
    var type: WebServerMessageType
    var success: Bool?
    var requestID: String?
    var payload: JSONValue?
    var message: String?
    var timestamp: Int64

    static func authSuccess(token: String) -> WebServerMessage {
        WebServerMessage(
            type: .authResult,
            success: true,
            message: token,
            timestamp: currentTimestamp()
        )
    }

    static func authFailure(_ reason: String) -> WebServerMessage {
        WebServerMessage(
            type: .authResult,
            success: false,
            message: reason,
            timestamp: currentTimestamp()
        )
    }

    static func error(_ msg: String, requestID: String? = nil) -> WebServerMessage {
        WebServerMessage(
            type: .error,
            success: false,
            requestID: requestID,
            message: msg,
            timestamp: currentTimestamp()
        )
    }

    static func pong(requestID: String? = nil) -> WebServerMessage {
        WebServerMessage(
            type: .pong,
            requestID: requestID,
            timestamp: currentTimestamp()
        )
    }

    static func snapshot(
        type: WebServerMessageType,
        payload: JSONValue,
        requestID: String? = nil
    ) -> WebServerMessage {
        WebServerMessage(
            type: type,
            success: true,
            requestID: requestID,
            payload: payload,
            timestamp: currentTimestamp()
        )
    }

    // MARK: - Chat streaming helpers

    static func textDelta(_ text: String, sessionID: String) -> WebServerMessage {
        WebServerMessage(
            type: .textDelta,
            payload: .object(["sessionID": .string(sessionID), "text": .string(text)]),
            timestamp: currentTimestamp()
        )
    }

    static func toolStart(id: String, name: String, input: String?, sessionID: String) -> WebServerMessage {
        var dict: [String: JSONValue] = [
            "sessionID": .string(sessionID),
            "toolId": .string(id),
            "name": .string(name)
        ]
        if let input { dict["input"] = .string(input) }
        return WebServerMessage(
            type: .toolStart,
            payload: .object(dict),
            timestamp: currentTimestamp()
        )
    }

    static func toolEnd(id: String, result: String?, sessionID: String) -> WebServerMessage {
        var dict: [String: JSONValue] = [
            "sessionID": .string(sessionID),
            "toolId": .string(id)
        ]
        if let result { dict["result"] = .string(result) }
        return WebServerMessage(
            type: .toolEnd,
            payload: .object(dict),
            timestamp: currentTimestamp()
        )
    }

    static func chatDone(sessionID: String) -> WebServerMessage {
        WebServerMessage(
            type: .chatDone,
            payload: .object(["sessionID": .string(sessionID)]),
            timestamp: currentTimestamp()
        )
    }

    static func chatError(_ msg: String, sessionID: String) -> WebServerMessage {
        WebServerMessage(
            type: .chatError,
            success: false,
            payload: .object(["sessionID": .string(sessionID)]),
            message: msg,
            timestamp: currentTimestamp()
        )
    }

    static func usageUpdate(sessionID: String, inputTokens: Int, cachedTokens: Int, outputTokens: Int, costUSD: Double?) -> WebServerMessage {
        var dict: [String: JSONValue] = [
            "sessionID": .string(sessionID),
            "inputTokens": .number(Double(inputTokens)),
            "cachedTokens": .number(Double(cachedTokens)),
            "outputTokens": .number(Double(outputTokens))
        ]
        if let cost = costUSD { dict["costUSD"] = .number(cost) }
        return WebServerMessage(
            type: .usageUpdate,
            payload: .object(dict),
            timestamp: currentTimestamp()
        )
    }

    private static func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Web Remote Status

struct WebRemoteStatus: Codable, Equatable, Sendable {
    var running: Bool
    var httpPort: Int?
    var wsPort: Int?
    var connectedClients: Int
    var lastError: String?

    static let idle = WebRemoteStatus(
        running: false,
        httpPort: nil,
        wsPort: nil,
        connectedClients: 0,
        lastError: nil
    )
}
