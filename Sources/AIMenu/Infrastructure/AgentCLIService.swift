import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Manages a single Agent CLI process: spawn, stream stdout JSONL events, abort.
final class AgentCLIService: @unchecked Sendable {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let queue = DispatchQueue(label: "aimenu.agent-cli", qos: .userInitiated)
    private var lineBuffer = Data()
    private var agentType: AgentType = .claude

    /// Called for each parsed event from CLI stdout
    var onEvent: (@Sendable (AgentStreamEvent) -> Void)?
    /// Called when the process exits。第二个参数是最终 stderr 文本。
    var onComplete: (@Sendable (Int32, String?) -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }
    var pid: Int32? { process?.processIdentifier }

    // MARK: - Spawn Claude

    func spawnClaude(
        message: String,
        resumeSessionId: String?,
        mode: AgentPermissionMode,
        model: String?,
        workingDirectory: URL
    ) throws {
        agentType = .claude

        guard let claudePath = Self.findCLI("claude") else {
            throw AppError.fileNotFound("claude CLI not found in PATH")
        }

        var args = ["-p", "--output-format", "stream-json", "--verbose"]

        switch mode {
        case .yolo:
            args.append("--dangerously-skip-permissions")
        case .plan:
            args += ["--permission-mode", "plan"]
        case .default:
            args += ["--permission-mode", "default"]
        }

        if let sessionId = resumeSessionId {
            args += ["--resume", sessionId]
        }

        if let model, !model.isEmpty {
            args += ["--model", model]
        }

        try spawn(
            command: claudePath,
            args: args,
            inputText: message,
            workDir: workingDirectory
        )
    }

    // MARK: - Spawn Codex

    func spawnCodex(
        message: String,
        resumeThreadId: String?,
        mode: AgentPermissionMode,
        model: String?,
        workingDirectory: URL
    ) throws {
        agentType = .codex

        guard let codexPath = Self.findCLI("codex") else {
            throw AppError.fileNotFound("codex CLI not found in PATH")
        }

        var args = ["exec", "--json", "--skip-git-repo-check"]

        if let threadId = resumeThreadId {
            // Sandbox flag must precede 'resume'
            if mode == .plan {
                args += ["-s", "read-only"]
            }
            args += ["resume", threadId]
        }

        switch mode {
        case .yolo:
            args.append("--dangerously-bypass-approvals-and-sandbox")
        case .plan:
            if resumeThreadId == nil {
                args += ["-s", "read-only"]
            }
        case .default:
            args.append("--full-auto")
        }

        if let model, !model.isEmpty {
            // Parse "gpt-5.4(high)" → base model + reasoning effort
            let (baseModel, effort) = Self.parseCodexModel(model)
            args += ["--model", baseModel]
            if let effort {
                args += ["-c", "model_reasoning_effort=\"\(effort)\""]
            }
        }

        if resumeThreadId != nil {
            // stdin marker must be last for resume
            args.append("-")
        } else {
            args += ["-C", workingDirectory.path, "-"]
        }

        try spawn(
            command: codexPath,
            args: args,
            inputText: message,
            workDir: workingDirectory
        )
    }

    // MARK: - Abort

    func abort() {
        guard let process, process.isRunning else { return }
        process.terminate()

        // Grace period then SIGKILL
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let proc = self.process, proc.isRunning else { return }
            kill(proc.processIdentifier, SIGKILL)
        }
    }

    // MARK: - Internal: Spawn Process

    private func spawn(
        command: String,
        args: [String],
        inputText: String,
        workDir: URL
    ) throws {
        // Clean up any existing process
        if let existing = process, existing.isRunning {
            existing.terminate()
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = args
        proc.currentDirectoryURL = workDir
        proc.environment = Self.buildEnvironment()

        // stdin: pipe with message
        let stdinPipe = Pipe()
        proc.standardInput = stdinPipe

        // stdout: pipe with readability handler for streaming
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        self.stdoutPipe = outPipe

        // stderr: capture for error reporting
        let errPipe = Pipe()
        proc.standardError = errPipe
        self.stderrPipe = errPipe

        lineBuffer = Data()

        // Real-time stdout reading
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — will be handled by terminationHandler
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { [weak self] in
                self?.processStdoutData(data)
            }
        }

        // Capture stderr using a thread-safe wrapper
        let stderrCapture = StderrCapture()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrCapture.append(data)
            } else {
                handle.readabilityHandler = nil
            }
        }

        // Termination handler
        proc.terminationHandler = { [weak self] process in
            // Stop the readability handler to prevent concurrent access
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            self?.queue.async { [weak self] in
                // Drain any remaining stdout data before flushing
                let remaining = outPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    self?.processStdoutData(remaining)
                }
                self?.flushLineBuffer()
                let errText = stderrCapture.text
                let terminalError = process.terminationStatus == 0 ? nil : errText.trimmedNonEmpty
                self?.onComplete?(process.terminationStatus, terminalError)
            }
        }

        self.process = proc

        NSLog("[AgentCLI] spawning: \(command) [\(args.count) args]")

        try proc.run()

        // Write message to stdin then close
        let inputData = Data(inputText.utf8)
        stdinPipe.fileHandleForWriting.write(inputData)
        stdinPipe.fileHandleForWriting.closeFile()
    }

    // MARK: - JSONL Line Processing

    private func processStdoutData(_ data: Data) {
        lineBuffer.append(data)

        // Split on newlines
        while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBuffer[lineBuffer.startIndex..<newlineIndex]
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            switch agentType {
            case .claude:
                parseClaudeLine(Data(lineData))
            case .codex:
                parseCodexLine(Data(lineData))
            }
        }
    }

    private func flushLineBuffer() {
        guard !lineBuffer.isEmpty else { return }
        switch agentType {
        case .claude:
            parseClaudeLine(lineBuffer)
        case .codex:
            parseCodexLine(lineBuffer)
        }
        lineBuffer = Data()
    }

    // MARK: - Claude JSONL Parser

    private func parseClaudeLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let type = json["type"] as? String else { return }

        switch type {
        case "system":
            if let sessionId = json["session_id"] as? String {
                onEvent?(.sessionInfo(cliSessionId: sessionId))
            }

        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }

            for item in content {
                guard let itemType = item["type"] as? String else { continue }

                switch itemType {
                case "text":
                    if let text = item["text"] as? String, !text.isEmpty {
                        onEvent?(.textDelta(text))
                    }
                case "tool_use":
                    let toolId = item["id"] as? String ?? UUID().uuidString
                    let toolName = item["name"] as? String ?? "unknown"
                    let inputJSON = item["input"]
                    let inputStr = inputJSON.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                        .flatMap { String(data: $0, encoding: .utf8) }
                    onEvent?(.toolStart(id: toolId, name: toolName, input: inputStr))
                case "tool_result":
                    let toolId = item["tool_use_id"] as? String ?? ""
                    let resultContent = item["content"] as? String
                    onEvent?(.toolEnd(id: toolId, result: resultContent))
                default:
                    break
                }
            }

        case "result":
            if let cost = json["total_cost_usd"] as? Double {
                onEvent?(.cost(usd: cost))
            }

        default:
            break
        }
    }

    // MARK: - Codex JSONL Parser

    private func parseCodexLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let type = json["type"] as? String else { return }

        switch type {
        case "thread.started":
            if let threadId = json["thread_id"] as? String {
                onEvent?(.codexThreadInfo(threadId: threadId))
            }

        case "item.started":
            if let item = json["item"] as? [String: Any] {
                let itemId = item["id"] as? String ?? UUID().uuidString
                let itemType = item["type"] as? String ?? "unknown"
                let toolName = Self.codexItemTypeName(itemType)
                onEvent?(.toolStart(id: itemId, name: toolName, input: nil))
            }

        case "item.completed":
            if let item = json["item"] as? [String: Any] {
                let itemId = item["id"] as? String ?? ""
                let itemType = item["type"] as? String ?? ""

                // Extract text or result
                let text = item["aggregated_output"] as? String
                    ?? item["text"] as? String
                    ?? item["output"] as? String

                if itemType == "message", let text, !text.isEmpty {
                    onEvent?(.textDelta(text))
                }

                onEvent?(.toolEnd(id: itemId, result: text))
            }

        case "turn.completed":
            if let usage = json["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let cached = usage["cached_input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                onEvent?(.usage(inputTokens: input, cachedTokens: cached, outputTokens: output))
            }

        case "turn.failed":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                onEvent?(.error(message))
            }

        case "error":
            if let message = json["message"] as? String {
                onEvent?(.error(message))
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private static func codexItemTypeName(_ itemType: String) -> String {
        switch itemType {
        case "command_execution": return "CommandExecution"
        case "mcp_tool_call": return "McpToolCall"
        case "file_change": return "FileChange"
        case "reasoning": return "Reasoning"
        default: return itemType
        }
    }

    private static func parseCodexModel(_ model: String) -> (base: String, effort: String?) {
        // Parse "gpt-5.4(high)" → ("gpt-5.4", "high")
        guard let parenStart = model.firstIndex(of: "("),
              let parenEnd = model.firstIndex(of: ")") else {
            return (model, nil)
        }
        let base = String(model[model.startIndex..<parenStart])
        let effort = String(model[model.index(after: parenStart)..<parenEnd])
        return (base, effort.isEmpty ? nil : effort)
    }

    private static let cliPathCacheLock = NSLock()
    private static nonisolated(unsafe) var _cliPathCache: [String: String] = [:]

    static func findCLI(_ name: String) -> String? {
        cliPathCacheLock.lock()
        let cached = _cliPathCache[name]
        cliPathCacheLock.unlock()
        if let cached, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let found = _findCLIUncached(name)
        if let found {
            cliPathCacheLock.lock()
            _cliPathCache[name] = found
            cliPathCacheLock.unlock()
        }
        return found
    }

    private static func _findCLIUncached(_ name: String) -> String? {
        let searchPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.cargo/bin",
            NSHomeDirectory() + "/.nvm/versions/node"  // nvm paths handled below
        ]

        // Direct check in common paths
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // nvm: search for latest node version
        let nvmBase = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for version in versions.sorted().reversed() {
                let path = "\(nvmBase)/\(version)/bin/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        // volta
        let voltaPath = NSHomeDirectory() + "/.volta/bin/\(name)"
        if FileManager.default.isExecutableFile(atPath: voltaPath) {
            return voltaPath
        }

        // Try which via shell
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice
        if let _ = try? whichProcess.run() {
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                let resolved = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                if !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Ensure common tool paths are in PATH
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.cargo/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let merged = (additionalPaths + [currentPath]).joined(separator: ":")
        env["PATH"] = merged

        return env
    }
}

// MARK: - Thread-safe stderr capture

private final class StderrCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    }
}
