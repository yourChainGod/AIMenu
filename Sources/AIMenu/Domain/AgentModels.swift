import Foundation

// MARK: - Agent Type

enum AgentType: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
}

// MARK: - Permission Mode

enum AgentPermissionMode: String, Codable, Sendable {
    case yolo
    case plan
    case `default`
}

// MARK: - Agent Session

struct AgentSession: Codable, Sendable, Identifiable {
    var id: String
    var agent: AgentType
    var title: String
    var messages: [AgentMessage]
    var permissionMode: AgentPermissionMode
    var model: String?
    var cwd: String?
    var cliSessionId: String?
    var codexThreadId: String?
    var createdAt: Int64
    var updatedAt: Int64
    var isRunning: Bool

    var summary: AgentSessionSummary {
        AgentSessionSummary(
            id: id,
            title: title,
            agent: agent,
            isRunning: isRunning,
            updatedAt: updatedAt
        )
    }

    static func create(
        agent: AgentType,
        mode: AgentPermissionMode,
        model: String?,
        cwd: String?
    ) -> AgentSession {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return AgentSession(
            id: UUID().uuidString,
            agent: agent,
            title: "New \(agent.rawValue) session",
            messages: [],
            permissionMode: mode,
            model: model,
            cwd: cwd,
            createdAt: now,
            updatedAt: now,
            isRunning: false
        )
    }
}

// MARK: - Agent Message

struct AgentMessage: Codable, Sendable {
    var role: AgentMessageRole
    var content: String
    var toolCalls: [AgentToolCall]?
    var timestamp: Int64

    static func user(_ text: String) -> AgentMessage {
        AgentMessage(
            role: .user,
            content: text,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    static func assistant(_ text: String, toolCalls: [AgentToolCall]? = nil) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: text,
            toolCalls: toolCalls,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

enum AgentMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Tool Call

struct AgentToolCall: Codable, Sendable {
    var id: String
    var name: String
    var input: String?
    var result: String?
    var isDone: Bool
}

// MARK: - Stream Events (from CLI stdout JSONL)

enum AgentStreamEvent: Sendable {
    case textDelta(String)
    case toolStart(id: String, name: String, input: String?)
    case toolEnd(id: String, result: String?)
    case sessionInfo(cliSessionId: String)
    case codexThreadInfo(threadId: String)
    case cost(usd: Double)
    case usage(inputTokens: Int, cachedTokens: Int, outputTokens: Int)
    case error(String)
    case done
}

// MARK: - Session Summary (for list view)

struct AgentSessionSummary: Codable, Sendable {
    var id: String
    var title: String
    var agent: AgentType
    var isRunning: Bool
    var updatedAt: Int64
}
