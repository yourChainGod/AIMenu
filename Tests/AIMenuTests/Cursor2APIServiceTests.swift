import XCTest
import Foundation
@testable import AIMenu

final class Cursor2APIServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocol.unregisterClass(MockCursor2APIHealthURLProtocol.self)
        MockCursor2APIHealthURLProtocol.reset()
        super.tearDown()
    }

    func testStatusSkipsHealthProbeWhenPortIsIdle() async throws {
        let tempRoot = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let session = makeSession()
        let service = Cursor2APIService(
            paths: makePaths(root: tempRoot),
            session: session,
            portService: MockPortManagementService(status: .idle(port: 8002))
        )

        let status = await service.status()

        XCTAssertFalse(status.running)
        XCTAssertEqual(MockCursor2APIHealthURLProtocol.requestCount, 0)
    }

    func testStatusProbesHealthWhenPortIsOccupied() async throws {
        let tempRoot = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let session = makeSession()
        MockCursor2APIHealthURLProtocol.responseStatusCode = 200
        let service = Cursor2APIService(
            paths: makePaths(root: tempRoot),
            session: session,
            portService: MockPortManagementService(
                status: ManagedPortStatus(
                    port: 8002,
                    occupied: true,
                    processID: 4321,
                    command: "cursor2api-go",
                    endpoint: "TCP 127.0.0.1:8002 (LISTEN)"
                )
            )
        )

        let status = await service.status()

        XCTAssertTrue(status.running)
        XCTAssertEqual(MockCursor2APIHealthURLProtocol.requestCount, 1)
        XCTAssertEqual(MockCursor2APIHealthURLProtocol.lastRequestURL?.absoluteString, "http://127.0.0.1:8002/health")
    }

    private func makeSession() -> URLSession {
        MockCursor2APIHealthURLProtocol.reset()
        URLProtocol.registerClass(MockCursor2APIHealthURLProtocol.self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockCursor2APIHealthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePaths(root: URL) -> FileSystemPaths {
        FileSystemPaths(
            applicationSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true),
            accountStorePath: root.appendingPathComponent("accounts.json", isDirectory: false),
            codexAuthPath: root.appendingPathComponent(".codex/auth.json", isDirectory: false),
            codexConfigPath: root.appendingPathComponent(".codex/config.toml", isDirectory: false),
            proxyDaemonDataDirectory: root.appendingPathComponent(".proxyd", isDirectory: true),
            proxyDaemonKeyPath: root.appendingPathComponent(".proxyd/key", isDirectory: false),
            cloudflaredLogDirectory: root.appendingPathComponent("cloudflared-logs", isDirectory: true),
            managedToolsDirectory: root.appendingPathComponent("managed-tools", isDirectory: true),
            cursor2APIDirectory: root.appendingPathComponent("managed-tools/cursor2api-go", isDirectory: true),
            cursor2APIBinaryPath: root.appendingPathComponent("managed-tools/cursor2api-go/cursor2api-go", isDirectory: false),
            cursor2APIConfigPath: root.appendingPathComponent("managed-tools/cursor2api-go/config.yaml", isDirectory: false),
            cursor2APILogDirectory: root.appendingPathComponent("managed-tools/cursor2api-go/logs", isDirectory: true)
        )
    }
}

private struct MockPortManagementService: PortManagementServiceProtocol {
    let status: ManagedPortStatus

    func status(for port: Int) async -> ManagedPortStatus {
        ManagedPortStatus(
            port: port,
            occupied: status.occupied,
            processID: status.processID,
            command: status.command,
            endpoint: status.endpoint
        )
    }

    func terminate(port: Int) async throws -> ManagedPortStatus {
        ManagedPortStatus.idle(port: port)
    }

    func forceKill(port: Int) async throws -> ManagedPortStatus {
        ManagedPortStatus.idle(port: port)
    }
}

private final class MockCursor2APIHealthURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var _requestCount = 0
    nonisolated(unsafe) private static var _responseStatusCode = 200
    nonisolated(unsafe) private static var _lastRequestURL: URL?
    private static let lock = NSLock()

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static var responseStatusCode: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _responseStatusCode
        }
        set {
            lock.lock()
            _responseStatusCode = newValue
            lock.unlock()
        }
    }

    static var lastRequestURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _lastRequestURL
    }

    static func reset() {
        lock.lock()
        _requestCount = 0
        _responseStatusCode = 200
        _lastRequestURL = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        Self._lastRequestURL = request.url
        let statusCode = Self._responseStatusCode
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
