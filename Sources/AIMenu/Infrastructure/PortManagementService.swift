import Foundation

#if os(macOS)
actor PortManagementService: PortManagementServiceProtocol {
    func status(for port: Int) async -> ManagedPortStatus {
        guard port > 0 else { return .idle(port: port) }
        guard let lsof = CommandRunner.resolveExecutable("lsof") else {
            return .idle(port: port)
        }

        let result = try? CommandRunner.run(
            lsof,
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"],
            timeout: 1.5
        )

        guard let stdout = result?.stdout, !(stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            return .idle(port: port)
        }

        let lines = stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return .idle(port: port) }
        let parts = lines[1].split(whereSeparator: \.isWhitespace).map(String.init)

        let command = parts.first
        let pid = parts.count > 1 ? Int(parts[1]) : nil
        let endpoint = parts.last

        return ManagedPortStatus(
            port: port,
            occupied: true,
            processID: pid,
            command: command,
            endpoint: endpoint
        )
    }

    func terminate(port: Int) async throws -> ManagedPortStatus {
        guard port > 0 else {
            throw AppError.invalidData("端口号无效")
        }
        let pids = try listeningProcessIDs(for: port)
        guard !pids.isEmpty else { return await status(for: port) }

        try send(signal: "-TERM", to: pids, errorPrefix: "结束端口进程失败")
        try? await Task.sleep(for: .milliseconds(250))

        let refreshed = await status(for: port)
        guard !refreshed.occupied else {
            throw AppError.invalidData("端口 \(port) 仍被占用，请尝试强制解除占用")
        }

        return refreshed
    }

    func forceKill(port: Int) async throws -> ManagedPortStatus {
        guard port > 0 else {
            throw AppError.invalidData("端口号无效")
        }
        let pids = try listeningProcessIDs(for: port)
        guard !pids.isEmpty else { return await status(for: port) }

        try send(signal: "-KILL", to: pids, errorPrefix: "强制结束端口进程失败")
        try? await Task.sleep(for: .milliseconds(250))
        return await status(for: port)
    }

    private func listeningProcessIDs(for port: Int) throws -> [Int] {
        guard let lsof = CommandRunner.resolveExecutable("lsof") else {
            throw AppError.fileNotFound("系统缺少 lsof，无法释放端口")
        }

        let pidResult = try CommandRunner.run(
            lsof,
            arguments: ["-tiTCP:\(port)", "-sTCP:LISTEN"],
            timeout: 1.5
        )

        return pidResult.stdout
            .components(separatedBy: .newlines)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func send(signal: String, to pids: [Int], errorPrefix: String) throws {
        let pidStrings = pids.map(String.init)
        _ = try CommandRunner.runChecked(
            "/bin/kill",
            arguments: [signal] + pidStrings,
            timeout: 1.5,
            errorPrefix: errorPrefix
        )
    }
}
#else
actor PortManagementService: PortManagementServiceProtocol {
    func status(for port: Int) async -> ManagedPortStatus { .idle(port: port) }
    func terminate(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
    func forceKill(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
}
#endif
