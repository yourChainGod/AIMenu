import Foundation

actor AgentSessionStore {
    private let directory: URL
    private var cache: [String: AgentSession] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - CRUD

    func createSession(
        agent: AgentType,
        mode: AgentPermissionMode,
        model: String?,
        cwd: String?
    ) throws -> AgentSession {
        try ensureDirectory()
        let session = AgentSession.create(agent: agent, mode: mode, model: model, cwd: cwd)
        try persist(session)
        return session
    }

    func listSessions() throws -> [AgentSessionSummary] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var summaries: [AgentSessionSummary] = []
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            if let session = try? loadSession(id: id) {
                summaries.append(session.summary)
            }
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadSession(id: String) throws -> AgentSession? {
        if let cached = cache[id] { return cached }

        let path = sessionPath(id)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        let data = try Data(contentsOf: path)
        let session = try JSONDecoder().decode(AgentSession.self, from: data)
        cache[id] = session
        return session
    }

    func saveSession(_ session: AgentSession) throws {
        try ensureDirectory()
        try persist(session)
    }

    func deleteSession(id: String) throws {
        cache.removeValue(forKey: id)
        let path = sessionPath(id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    // MARK: - Internal

    private func persist(_ session: AgentSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: sessionPath(session.id), options: .atomic)
        cache[session.id] = session
    }

    private func sessionPath(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
