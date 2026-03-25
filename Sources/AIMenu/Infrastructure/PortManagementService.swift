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
            timeout: NetworkConfig.portCheckTimeoutSeconds
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
            throw AppError.invalidData(L10n.tr("error.port.invalid_port"))
        }
        let pids = try listeningProcessIDs(for: port)
        guard !pids.isEmpty else { return await status(for: port) }

        try send(signal: "-TERM", to: pids, errorPrefix: L10n.tr("error.port.terminate_failed"))
        try? await Task.sleep(for: .milliseconds(250))

        let refreshed = await status(for: port)
        guard !refreshed.occupied else {
            throw AppError.invalidData(L10n.tr("error.port.still_occupied_format", String(port)))
        }

        return refreshed
    }

    func forceKill(port: Int) async throws -> ManagedPortStatus {
        guard port > 0 else {
            throw AppError.invalidData(L10n.tr("error.port.invalid_port"))
        }
        let pids = try listeningProcessIDs(for: port)
        guard !pids.isEmpty else { return await status(for: port) }

        try send(signal: "-KILL", to: pids, errorPrefix: L10n.tr("error.port.force_kill_failed"))
        try? await Task.sleep(for: .milliseconds(250))
        return await status(for: port)
    }

    /// Scan all TCP LISTEN ports on the machine
    func scanListeningPorts() async -> [ManagedPortStatus] {
        guard let lsof = CommandRunner.resolveExecutable("lsof") else { return [] }

        let result = try? CommandRunner.run(
            lsof,
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"],
            timeout: 5
        )

        guard let stdout = result?.stdout, !stdout.isEmpty else { return [] }

        let lines = stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }

        var seen = Set<Int>()
        var statuses: [ManagedPortStatus] = []

        for line in lines.dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 9 else { continue }

            let command = parts[0]
            let pid = Int(parts[1])
            let endpoint = parts[8]

            // Extract port from endpoint like "*:8787" or "127.0.0.1:3000"
            guard let colonIdx = endpoint.lastIndex(of: ":") else { continue }
            let portStr = String(endpoint[endpoint.index(after: colonIdx)...])
            guard let port = Int(portStr), port > 0, !seen.contains(port) else { continue }
            seen.insert(port)

            statuses.append(ManagedPortStatus(
                port: port,
                occupied: true,
                processID: pid,
                command: command,
                endpoint: endpoint
            ))
        }

        return statuses.sorted { $0.port < $1.port }
    }

    private func listeningProcessIDs(for port: Int) throws -> [Int] {
        guard let lsof = CommandRunner.resolveExecutable("lsof") else {
            throw AppError.fileNotFound(L10n.tr("error.port.lsof_missing"))
        }

        let pidResult = try CommandRunner.run(
            lsof,
            arguments: ["-tiTCP:\(port)", "-sTCP:LISTEN"],
            timeout: NetworkConfig.portCheckTimeoutSeconds
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
            timeout: NetworkConfig.portCheckTimeoutSeconds,
            errorPrefix: errorPrefix
        )
    }
}
#else
actor PortManagementService: PortManagementServiceProtocol {
    func status(for port: Int) async -> ManagedPortStatus { .idle(port: port) }
    func terminate(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
    func forceKill(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
    func scanListeningPorts() async -> [ManagedPortStatus] { [] }
}
#endif
