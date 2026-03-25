import XCTest
@testable import AIMenu

final class WebSessionManagerTests: XCTestCase {
    private let encoder = JSONEncoder()

    // MARK: - Auth Flow

    func testUnauthenticatedMessageRejected() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let msg = WebClientMessage(type: .requestAccounts, requestID: "r1")
        let msgData = try encoder.encode(msg)
        let responseData = await manager.handleMessage(data: msgData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .error)
        XCTAssertEqual(decoded.message, "Not authenticated")
    }

    func testAuthWithCorrectToken() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let authMsg = WebClientMessage(type: .auth, token: "secret")
        let authData = try encoder.encode(authMsg)
        let responseData = await manager.handleMessage(data: authData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .authResult)
        XCTAssertEqual(decoded.success, true)

        let count = await manager.authenticatedConnectionCount()
        XCTAssertEqual(count, 1)
    }

    func testAuthWithWrongToken() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let authMsg = WebClientMessage(type: .auth, token: "wrong")
        let authData = try encoder.encode(authMsg)
        let responseData = await manager.handleMessage(data: authData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .authResult)
        XCTAssertEqual(decoded.success, false)

        let count = await manager.authenticatedConnectionCount()
        XCTAssertEqual(count, 0)
    }

    func testAuthWithEmptyToken() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let authMsg = WebClientMessage(type: .auth, token: "")
        let authData = try encoder.encode(authMsg)
        let responseData = await manager.handleMessage(data: authData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.success, false)
        XCTAssertEqual(decoded.message, "Token required")
    }

    // MARK: - Ping

    func testPingAlwaysWorks() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let pingMsg = WebClientMessage(type: .ping, requestID: "p1")
        let pingData = try encoder.encode(pingMsg)
        let responseData = await manager.handleMessage(data: pingData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .pong)
        XCTAssertEqual(decoded.requestID, "p1")
    }

    // MARK: - Disconnect

    func testDisconnectRemovesConnection() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        // Authenticate first
        let authMsg = WebClientMessage(type: .auth, token: "secret")
        _ = await manager.handleMessage(data: try encoder.encode(authMsg), from: "c1")

        let countBefore = await manager.authenticatedConnectionCount()
        XCTAssertEqual(countBefore, 1)

        await manager.handleDisconnect(id: "c1")

        let countAfter = await manager.authenticatedConnectionCount()
        XCTAssertEqual(countAfter, 0)

        let total = await manager.totalConnectionCount()
        XCTAssertEqual(total, 0)
    }

    // MARK: - Message Delegation

    func testAuthenticatedMessageDelegated() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        let capture = MessageCapture()

        await manager.setOnAuthenticatedMessage { @Sendable connID, msg in
            await capture.set(connectionID: connID, message: msg)
            return WebServerMessage.snapshot(
                type: .accountsSnapshot,
                payload: .object(["count": .number(3)]),
                requestID: msg.requestID
            )
        }

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        // Authenticate
        let authMsg = WebClientMessage(type: .auth, token: "secret")
        _ = await manager.handleMessage(data: try encoder.encode(authMsg), from: "c1")

        // Send data request
        let dataMsg = WebClientMessage(type: .requestAccounts, requestID: "r1")
        let responseData = await manager.handleMessage(data: try encoder.encode(dataMsg), from: "c1")

        let capturedID = await capture.connectionID
        let capturedMsg = await capture.message
        XCTAssertEqual(capturedID, "c1")
        XCTAssertEqual(capturedMsg?.type, .requestAccounts)

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .accountsSnapshot)
        XCTAssertEqual(decoded.requestID, "r1")
    }

    // MARK: - Invalid Data

    func testInvalidJSONReturnsError() async throws {
        let auth = WebRemoteAuthService(initialToken: "secret")
        let manager = WebSessionManager(authService: auth)

        await manager.handleConnect(id: "c1", remoteAddress: "127.0.0.1")

        let badData = Data("not json".utf8)
        let responseData = await manager.handleMessage(data: badData, from: "c1")

        let response = try XCTUnwrap(responseData)
        let decoded = try JSONDecoder().decode(WebServerMessage.self, from: response)
        XCTAssertEqual(decoded.type, .error)
        XCTAssertEqual(decoded.message, "Invalid message format")
    }
}

// Thread-safe capture for @Sendable closures
private actor MessageCapture {
    var connectionID: String?
    var message: WebClientMessage?

    func set(connectionID: String, message: WebClientMessage) {
        self.connectionID = connectionID
        self.message = message
    }
}
