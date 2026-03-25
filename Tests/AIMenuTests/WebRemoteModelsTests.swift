import XCTest
@testable import AIMenu

final class WebRemoteModelsTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - WebClientMessage Codable round-trip

    func testClientMessageCodableRoundTrip() throws {
        let original = WebClientMessage(type: .auth, token: "test-token", requestID: "req-1")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebClientMessage.self, from: data)
        XCTAssertEqual(decoded.type, .auth)
        XCTAssertEqual(decoded.token, "test-token")
        XCTAssertEqual(decoded.requestID, "req-1")
    }

    func testClientMessageWithNilFields() throws {
        let original = WebClientMessage(type: .ping, token: nil, requestID: nil)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebClientMessage.self, from: data)
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertNil(decoded.token)
        XCTAssertNil(decoded.requestID)
    }

    func testAllClientMessageTypes() throws {
        let types: [WebClientMessageType] = [.auth, .ping, .requestAccounts, .requestProviders, .requestProxyStatus]
        for msgType in types {
            let msg = WebClientMessage(type: msgType)
            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(WebClientMessage.self, from: data)
            XCTAssertEqual(decoded.type, msgType, "Round-trip failed for \(msgType)")
        }
    }

    // MARK: - WebServerMessage Codable round-trip

    func testServerMessageCodableRoundTrip() throws {
        let original = WebServerMessage.error("something broke", requestID: "req-2")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebServerMessage.self, from: data)
        XCTAssertEqual(decoded.type, .error)
        XCTAssertEqual(decoded.success, false)
        XCTAssertEqual(decoded.requestID, "req-2")
        XCTAssertEqual(decoded.message, "something broke")
        XCTAssertGreaterThan(decoded.timestamp, 0)
    }

    func testServerMessagePong() throws {
        let original = WebServerMessage.pong(requestID: "ping-1")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebServerMessage.self, from: data)
        XCTAssertEqual(decoded.type, .pong)
        XCTAssertEqual(decoded.requestID, "ping-1")
    }

    func testServerMessageAuthSuccess() throws {
        let original = WebServerMessage.authSuccess(token: "web-abc")
        XCTAssertEqual(original.type, .authResult)
        XCTAssertEqual(original.success, true)
        XCTAssertEqual(original.message, "web-abc")
    }

    func testServerMessageAuthFailure() throws {
        let original = WebServerMessage.authFailure("banned")
        XCTAssertEqual(original.type, .authResult)
        XCTAssertEqual(original.success, false)
        XCTAssertEqual(original.message, "banned")
    }

    func testServerMessageSnapshot() throws {
        let payload = JSONValue.object(["count": .number(5)])
        let original = WebServerMessage.snapshot(type: .accountsSnapshot, payload: payload, requestID: "r1")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebServerMessage.self, from: data)
        XCTAssertEqual(decoded.type, .accountsSnapshot)
        XCTAssertEqual(decoded.success, true)
        XCTAssertEqual(decoded.requestID, "r1")
        XCTAssertEqual(decoded.payload, payload)
    }

    // MARK: - WebRemoteStatus

    func testWebRemoteStatusIdle() {
        let status = WebRemoteStatus.idle
        XCTAssertFalse(status.running)
        XCTAssertNil(status.httpPort)
        XCTAssertNil(status.wsPort)
        XCTAssertEqual(status.connectedClients, 0)
        XCTAssertNil(status.lastError)
    }

    func testWebRemoteStatusCodable() throws {
        let original = WebRemoteStatus(running: true, httpPort: 9090, wsPort: 9091, connectedClients: 3, lastError: nil)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebRemoteStatus.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testWebRemoteStatusEquatable() {
        let a = WebRemoteStatus(running: true, httpPort: 9090, wsPort: 9091, connectedClients: 1)
        let b = WebRemoteStatus(running: true, httpPort: 9090, wsPort: 9091, connectedClients: 1)
        let c = WebRemoteStatus(running: false, httpPort: nil, wsPort: nil, connectedClients: 0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
