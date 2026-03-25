import Foundation

actor AgentRuntimeCoordinator {
    private struct RunningProcessState {
        let runID: UUID
        let cli: AgentCLIService

        var isRunning: Bool { cli.isRunning }
    }

    private let sessionStore: AgentSessionStore
    private var runningProcesses: [String: RunningProcessState] = [:]

    /// Stream event callback: (sessionId, WebServerMessage) → broadcast to WS clients
    var onStreamEvent: (@Sendable (String, WebServerMessage) async -> Void)?

    init(sessionStore: AgentSessionStore) {
        self.sessionStore = sessionStore
    }

    func setOnStreamEvent(_ handler: (@Sendable (String, WebServerMessage) async -> Void)?) {
        self.onStreamEvent = handler
    }

    // MARK: - Session CRUD

    func listSessions() async throws -> [AgentSessionSummary] {
        var summaries = try await sessionStore.listSessions()
        // Update running status from live process state
        for i in summaries.indices {
            summaries[i].isRunning = runningProcesses[summaries[i].id]?.isRunning ?? false
        }
        return summaries
    }

    func loadSession(id: String) async throws -> AgentSession? {
        guard var session = try await sessionStore.loadSession(id: id) else { return nil }
        session.isRunning = runningProcesses[id]?.isRunning ?? false
        return session
    }

    func createSession(
        agent: AgentType,
        mode: AgentPermissionMode,
        model: String?,
        cwd: String?
    ) async throws -> AgentSession {
        try await sessionStore.createSession(agent: agent, mode: mode, model: model, cwd: cwd)
    }

    func deleteSession(id: String) async throws {
        // Abort if running
        await abortSession(id: id)
        try await sessionStore.deleteSession(id: id)
    }

    // MARK: - Send Message (spawn or resume agent)

    func sendMessage(sessionId: String, text: String) async throws {
        guard var session = try await sessionStore.loadSession(id: sessionId) else {
            throw AppError.invalidData("Session not found: \(sessionId)")
        }

        // Abort existing process if still running
        if let existing = runningProcesses[sessionId], existing.isRunning {
            existing.cli.abort()
            runningProcesses.removeValue(forKey: sessionId)
        }

        // Append user message
        session.messages.append(AgentMessage.user(text))
        session.isRunning = true
        session.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try await sessionStore.saveSession(session)

        // Spawn process
        let cli = AgentCLIService()
        let runID = UUID()
        let workDir = URL(fileURLWithPath: session.cwd ?? NSHomeDirectory())

        // Record working directory in history
        if let cwd = session.cwd {
            WebCoordinator.addDirectoryToHistory(cwd)
        }

        // Accumulate assistant response
        let responseAccumulator = ResponseAccumulator()

        // Wire events
        cli.onEvent = { [weak self] event in
            guard let self else { return }
            Task {
                await self.handleStreamEvent(
                    event,
                    sessionId: sessionId,
                    runID: runID,
                    accumulator: responseAccumulator
                )
            }
        }

        cli.onComplete = { [weak self] exitCode, terminalError in
            guard let self else { return }
            Task {
                await self.handleProcessComplete(
                    sessionId: sessionId,
                    runID: runID,
                    exitCode: exitCode,
                    terminalError: terminalError,
                    accumulator: responseAccumulator
                )
            }
        }

        runningProcesses[sessionId] = RunningProcessState(runID: runID, cli: cli)

        do {
            switch session.agent {
            case .claude:
                try cli.spawnClaude(
                    message: text,
                    resumeSessionId: session.cliSessionId,
                    mode: session.permissionMode,
                    model: session.model,
                    workingDirectory: workDir
                )
            case .codex:
                try cli.spawnCodex(
                    message: text,
                    resumeThreadId: session.codexThreadId,
                    mode: session.permissionMode,
                    model: session.model,
                    workingDirectory: workDir
                )
            }
        } catch {
            if runningProcesses[sessionId]?.runID == runID {
                runningProcesses.removeValue(forKey: sessionId)
            }
            session.isRunning = false
            session.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try? await sessionStore.saveSession(session)
            throw error
        }
    }

    // MARK: - Abort

    func abortSession(id: String) async {
        if let state = runningProcesses[id] {
            state.cli.abort()
            runningProcesses.removeValue(forKey: id)
        }
        // Update session state
        if var session = try? await sessionStore.loadSession(id: id) {
            session.isRunning = false
            try? await sessionStore.saveSession(session)
        }
    }

    func isSessionRunning(_ sessionId: String) -> Bool {
        runningProcesses[sessionId]?.isRunning ?? false
    }

    func renameSession(id: String, title: String) async throws {
        guard var session = try await sessionStore.loadSession(id: id) else {
            throw AppError.invalidData("Session not found: \(id)")
        }
        session.title = title
        session.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try await sessionStore.saveSession(session)
    }

    // MARK: - Event Handling

    private func handleStreamEvent(
        _ event: AgentStreamEvent,
        sessionId: String,
        runID: UUID,
        accumulator: ResponseAccumulator
    ) async {
        guard runningProcesses[sessionId]?.runID == runID else { return }
        let message: WebServerMessage

        switch event {
        case .textDelta(let text):
            accumulator.appendText(text)
            message = .textDelta(text, sessionID: sessionId)

        case .toolStart(let id, let name, let input):
            accumulator.startTool(AgentToolCall(id: id, name: name, input: input, result: nil, isDone: false))
            message = .toolStart(id: id, name: name, input: input, sessionID: sessionId)

        case .toolEnd(let id, let result):
            accumulator.endTool(id: id, result: result)
            message = .toolEnd(id: id, result: result, sessionID: sessionId)

        case .sessionInfo(let cliSessionId):
            // Save claude session ID for --resume
            if var session = try? await sessionStore.loadSession(id: sessionId) {
                session.cliSessionId = cliSessionId
                try? await sessionStore.saveSession(session)
            }
            return

        case .codexThreadInfo(let threadId):
            // Save codex thread ID for resume
            if var session = try? await sessionStore.loadSession(id: sessionId) {
                session.codexThreadId = threadId
                try? await sessionStore.saveSession(session)
            }
            return

        case .cost(let usd):
            message = .usageUpdate(sessionID: sessionId, inputTokens: 0, cachedTokens: 0, outputTokens: 0, costUSD: usd)

        case .usage(let input, let cached, let output):
            message = .usageUpdate(sessionID: sessionId, inputTokens: input, cachedTokens: cached, outputTokens: output, costUSD: nil)

        case .error(let msg):
            message = .chatError(msg, sessionID: sessionId)

        case .done:
            return
        }

        await onStreamEvent?(sessionId, message)
    }

    private func handleProcessComplete(
        sessionId: String,
        runID: UUID,
        exitCode: Int32,
        terminalError: String?,
        accumulator: ResponseAccumulator
    ) async {
        guard runningProcesses[sessionId]?.runID == runID else { return }

        // Save assistant response to session BEFORE removing from runningProcesses
        // so that late-arriving stream events can still pass the runID guard
        if var session = try? await sessionStore.loadSession(id: sessionId) {
            let responseText = accumulator.text
            if !responseText.isEmpty {
                let assistantMsg = AgentMessage.assistant(responseText, toolCalls: accumulator.toolCalls)
                session.messages.append(assistantMsg)
            }
            session.isRunning = false
            session.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)

            // Auto-title from first assistant response
            if session.title.hasPrefix("New "), !responseText.isEmpty {
                let titlePreview = String(responseText.prefix(60))
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !titlePreview.isEmpty {
                    session.title = titlePreview
                }
            }

            try? await sessionStore.saveSession(session)
        }

        // Now safe to remove — all data has been persisted
        runningProcesses.removeValue(forKey: sessionId)

        if let terminalError {
            await onStreamEvent?(sessionId, .chatError(terminalError, sessionID: sessionId))
        } else if exitCode != 0 {
            await onStreamEvent?(sessionId, .chatError("Process exited with code \(exitCode)", sessionID: sessionId))
        }

        // Notify done
        await onStreamEvent?(sessionId, .chatDone(sessionID: sessionId))
    }
}

// MARK: - Response Accumulator (thread-safe)

private final class ResponseAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _text = ""
    private var _toolCalls: [AgentToolCall] = []

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return _text
    }

    var toolCalls: [AgentToolCall] {
        lock.lock()
        defer { lock.unlock() }
        return _toolCalls
    }

    func appendText(_ text: String) {
        lock.lock()
        _text += text
        lock.unlock()
    }

    func startTool(_ tool: AgentToolCall) {
        lock.lock()
        _toolCalls.append(tool)
        lock.unlock()
    }

    func endTool(id: String, result: String?) {
        lock.lock()
        if let index = _toolCalls.firstIndex(where: { $0.id == id }) {
            _toolCalls[index].result = result
            _toolCalls[index].isDone = true
        }
        lock.unlock()
    }
}
