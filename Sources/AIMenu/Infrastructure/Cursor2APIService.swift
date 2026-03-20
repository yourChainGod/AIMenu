import Foundation

#if os(macOS)
actor Cursor2APIService: Cursor2APIServiceProtocol {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
        }

        var assets: [Asset]
    }

    private let paths: FileSystemPaths
    private let fileManager: FileManager
    private let session: URLSession
    private let portService: PortManagementServiceProtocol

    private var process: Process?
    private var logPath: URL?
    private var lastError: String?

    init(
        paths: FileSystemPaths,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        portService: PortManagementServiceProtocol
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.session = session
        self.portService = portService
    }

    func status() async -> Cursor2APIStatus {
        let config = loadConfig()
        let port = config.port ?? 8002
        let apiKey = config.apiKey ?? "0000"
        let baseURL = "http://127.0.0.1:\(port)"
        let installed = fileManager.isExecutableFile(atPath: paths.cursor2APIBinaryPath.path)
        let processAlive = process?.isRunning == true
        let healthAlive = await isHealthy(baseURL: baseURL)

        if !(processAlive || healthAlive) {
            process = nil
        }

        return Cursor2APIStatus(
            installed: installed,
            running: processAlive || healthAlive,
            port: port,
            apiKey: apiKey,
            baseURL: baseURL,
            binaryPath: installed ? paths.cursor2APIBinaryPath.path : nil,
            configPath: fileManager.fileExists(atPath: paths.cursor2APIConfigPath.path) ? paths.cursor2APIConfigPath.path : nil,
            logPath: logPath?.path,
            models: config.models,
            lastError: lastError
        )
    }

    func install() async throws -> Cursor2APIStatus {
        if fileManager.isExecutableFile(atPath: paths.cursor2APIBinaryPath.path) {
            return await status()
        }

        try prepareDirectories()
        let asset = try await latestReleaseAsset()
        guard let downloadURL = URL(string: asset.browser_download_url) else {
            throw AppError.invalidData("Cursor2API 下载地址无效")
        }

        var request = URLRequest(url: downloadURL)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")

        let (tempURL, _) = try await session.download(for: request)
        if fileManager.fileExists(atPath: paths.cursor2APIBinaryPath.path) {
            try? fileManager.removeItem(at: paths.cursor2APIBinaryPath)
        }
        try fileManager.moveItem(at: tempURL, to: paths.cursor2APIBinaryPath)
        try setExecutablePermission(at: paths.cursor2APIBinaryPath)

        return await status()
    }

    func start(port: Int?, apiKey: String?, models: [String]) async throws -> Cursor2APIStatus {
        if !fileManager.isExecutableFile(atPath: paths.cursor2APIBinaryPath.path) {
            _ = try await install()
        }

        let current = await status()
        if current.running {
            return current
        }

        try prepareDirectories()

        let resolvedPort = port ?? current.port
        let resolvedAPIKey = apiKey?.trimmedNonEmpty ?? current.apiKey
        let resolvedModels = models.compactMap(\.trimmedNonEmpty)
        let finalModels = resolvedModels.isEmpty ? defaultModels : resolvedModels

        let occupied = await portService.status(for: resolvedPort)
        if occupied.occupied {
            let processLabel = occupied.command ?? "未知进程"
            throw AppError.invalidData("端口 \(resolvedPort) 已被 \(processLabel) 占用，请先释放端口。")
        }

        try writeConfig(
            port: resolvedPort,
            apiKey: resolvedAPIKey,
            models: finalModels
        )

        let newLogPath = try nextLogPath()
        let command = Process()
        command.executableURL = paths.cursor2APIBinaryPath
        command.currentDirectoryURL = paths.cursor2APIDirectory
        command.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        command.standardOutput = stdoutPipe
        command.standardError = stderrPipe

        if fileManager.fileExists(atPath: newLogPath.path) {
            try? fileManager.removeItem(at: newLogPath)
        }
        _ = fileManager.createFile(atPath: newLogPath.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: newLogPath) {
            stdoutPipe.fileHandleForReading.readabilityHandler = { source in
                let data = source.availableData
                guard !data.isEmpty else { return }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { source in
                let data = source.availableData
                guard !data.isEmpty else { return }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }

        do {
            try command.run()
        } catch {
            throw AppError.io("启动 Cursor2API 失败：\(error.localizedDescription)")
        }

        process = command
        logPath = newLogPath
        lastError = nil

        for _ in 0..<20 {
            if await isHealthy(baseURL: "http://127.0.0.1:\(resolvedPort)") {
                return await status()
            }
            if command.isRunning == false {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        let logTail = (try? String(contentsOf: newLogPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = logTail?.trimmedNonEmpty ?? "Cursor2API 启动后未通过健康检查"
        if command.isRunning {
            command.terminate()
        }
        process = nil
        throw AppError.io(lastError ?? "Cursor2API 启动失败")
    }

    func stop() async -> Cursor2APIStatus {
        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning {
                process.interrupt()
            }
        } else {
            let current = await status()
            if current.running {
                do {
                    _ = try await portService.terminate(port: current.port)
                } catch {
                    _ = try? await portService.forceKill(port: current.port)
                }
            }
        }

        process = nil
        return await status()
    }

    private var defaultModels: [String] {
        [
            "claude-sonnet-4.6",
            "claude-sonnet-4-20250514",
            "claude-3-5-sonnet-20241022"
        ]
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: paths.cursor2APIDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cursor2APILogDirectory, withIntermediateDirectories: true)
    }

    private func latestReleaseAsset() async throws -> GitHubRelease.Asset {
        guard let url = URL(string: "https://api.github.com/repos/yourChainGod/cursor2api-go/releases/latest") else {
            throw AppError.invalidData("Cursor2API Release 地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #if arch(arm64)
        let preferredKeywords = ["darwin-arm64", "macos-arm64"]
        #else
        let preferredKeywords = ["darwin-amd64", "darwin-x86_64", "macos-amd64"]
        #endif

        for keyword in preferredKeywords {
            if let asset = release.assets.first(where: { $0.name.localizedCaseInsensitiveContains(keyword) }) {
                return asset
            }
        }

        if let fallback = release.assets.first(where: { $0.name.localizedCaseInsensitiveContains("darwin") }) {
            return fallback
        }

        throw AppError.invalidData("未找到适用于当前 macOS 的 Cursor2API 二进制")
    }

    private func writeConfig(port: Int, apiKey: String, models: [String]) throws {
        let content = """
        # Managed by AIMenu
        port: \(port)
        debug: false
        api_key: "\(apiKey)"
        models: "\(models.joined(separator: ","))"
        system_prompt_inject: ""
        timeout: 120
        max_input_length: 200000
        
        fingerprint:
          user_agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
        
        vision:
          enabled: false
          mode: api
          base_url: https://api.openai.com/v1/chat/completions
          api_key: ""
          model: gpt-4o-mini
        """

        try content.write(to: paths.cursor2APIConfigPath, atomically: true, encoding: .utf8)
        #if canImport(Darwin)
        _ = chmod(paths.cursor2APIConfigPath.path, S_IRUSR | S_IWUSR)
        #endif
    }

    private func loadConfig() -> (port: Int?, apiKey: String?, models: [String]) {
        guard fileManager.fileExists(atPath: paths.cursor2APIConfigPath.path),
              let content = try? String(contentsOf: paths.cursor2APIConfigPath, encoding: .utf8) else {
            return (nil, nil, [])
        }

        var port: Int?
        var apiKey: String?
        var models: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let split = line.firstIndex(of: ":") else {
                continue
            }
            let key = String(line[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch key {
            case "port":
                port = Int(value)
            case "api_key":
                apiKey = value
            case "models":
                models = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            default:
                break
            }
        }

        return (port, apiKey, models)
    }

    private func nextLogPath() throws -> URL {
        try fileManager.createDirectory(at: paths.cursor2APILogDirectory, withIntermediateDirectories: true)
        return paths.cursor2APILogDirectory
            .appendingPathComponent("cursor2api-\(Int(Date().timeIntervalSince1970)).log")
    }

    private func isHealthy(baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.2
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func setExecutablePermission(at url: URL) throws {
        #if canImport(Darwin)
        guard chmod(url.path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) == 0 else {
            throw AppError.io("无法设置 Cursor2API 执行权限")
        }
        #endif
    }
}
#else
actor Cursor2APIService: Cursor2APIServiceProtocol {
    func status() async -> Cursor2APIStatus { .idle }
    func install() async throws -> Cursor2APIStatus { .idle }
    func start(port: Int?, apiKey: String?, models: [String]) async throws -> Cursor2APIStatus { .idle }
    func stop() async -> Cursor2APIStatus { .idle }
}
#endif
