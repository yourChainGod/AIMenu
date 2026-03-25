import XCTest
@testable import AIMenu

final class AgentSessionStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: AgentSessionStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = AgentSessionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreateSession() async throws {
        let session = try await store.createSession(
            agent: .claude, mode: .default, model: "opus", cwd: "/tmp"
        )
        XCTAssertEqual(session.agent, .claude)
        XCTAssertEqual(session.permissionMode, .default)
        XCTAssertEqual(session.model, "opus")
        XCTAssertFalse(session.id.isEmpty)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertFalse(session.isRunning)
    }

    func testSaveAndLoadSession() async throws {
        var session = try await store.createSession(
            agent: .codex, mode: .yolo, model: nil, cwd: nil
        )
        session.messages.append(AgentMessage.user("Hello"))
        session.title = "Test Session"
        try await store.saveSession(session)

        // Load from file (bypass cache by creating new store)
        let freshStore = AgentSessionStore(directory: tempDir)
        let loaded = try await freshStore.loadSession(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Test Session")
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages.first?.content, "Hello")
        XCTAssertEqual(loaded?.agent, .codex)
    }

    func testListSessions() async throws {
        _ = try await store.createSession(agent: .claude, mode: .default, model: nil, cwd: nil)
        _ = try await store.createSession(agent: .codex, mode: .yolo, model: nil, cwd: nil)

        let list = try await store.listSessions()
        XCTAssertEqual(list.count, 2)
    }

    func testDeleteSession() async throws {
        let session = try await store.createSession(
            agent: .claude, mode: .default, model: nil, cwd: nil
        )
        try await store.deleteSession(id: session.id)

        let loaded = try await store.loadSession(id: session.id)
        XCTAssertNil(loaded)

        let list = try await store.listSessions()
        XCTAssertEqual(list.count, 0)
    }

    func testLoadNonExistentSession() async throws {
        let loaded = try await store.loadSession(id: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testSessionSummary() async throws {
        var session = try await store.createSession(
            agent: .claude, mode: .plan, model: "sonnet", cwd: nil
        )
        session.title = "My Plan"
        session.isRunning = true
        try await store.saveSession(session)

        let list = try await store.listSessions()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.title, "My Plan")
        XCTAssertEqual(list.first?.agent, .claude)
        XCTAssertEqual(list.first?.isRunning, true)
    }
}
