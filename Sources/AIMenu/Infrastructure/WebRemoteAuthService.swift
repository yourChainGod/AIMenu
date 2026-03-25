import Foundation
#if canImport(Darwin)
import Darwin
#endif

actor WebRemoteAuthService {
    private var token: String
    private let tokenFilePath: URL?
    private var failedAttempts: [String: (count: Int, lastAttempt: Date)] = [:]

    private static let maxAttempts = 5
    private static let banDuration: TimeInterval = 300

    init(initialToken: String? = nil, tokenFilePath: URL? = nil) {
        self.tokenFilePath = tokenFilePath

        // Priority: explicit token > file-persisted > generate new
        if let initialToken {
            self.token = initialToken
        } else if let filePath = tokenFilePath,
                  let saved = try? String(contentsOf: filePath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !saved.isEmpty {
            self.token = saved
            NSLog("[WebRemoteAuth] loaded persisted token from \(filePath.lastPathComponent)")
        } else {
            let generated = Self.generateToken()
            self.token = generated
            Self.persistToken(generated, to: tokenFilePath)
            NSLog("[WebRemoteAuth] generated and persisted new token")
        }
    }

    func currentToken() -> String {
        token
    }

    func regenerateToken() -> String {
        token = Self.generateToken()
        persistToken()
        return token
    }

    func setCustomToken(_ newToken: String) -> String {
        guard !newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return token
        }
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        persistToken()
        return token
    }

    func validate(candidateToken: String, remoteAddress: String) -> Bool {
        let banKey = normalizedAddress(remoteAddress)
        if isIPBanned(banKey) {
            return false
        }
        if candidateToken == token {
            failedAttempts.removeValue(forKey: banKey)
            return true
        }
        recordFailedAttempt(banKey)
        return false
    }

    func resetBans() {
        failedAttempts.removeAll()
    }

    func isIPBanned(_ address: String) -> Bool {
        let banKey = normalizedAddress(address)
        guard let entry = failedAttempts[banKey] else { return false }
        guard entry.count >= Self.maxAttempts else { return false }
        let elapsed = Date().timeIntervalSince(entry.lastAttempt)
        if elapsed > Self.banDuration {
            failedAttempts.removeValue(forKey: banKey)
            return false
        }
        return true
    }

    private func recordFailedAttempt(_ address: String) {
        let existing = failedAttempts[address]
        let newCount = (existing?.count ?? 0) + 1
        failedAttempts[address] = (count: newCount, lastAttempt: Date())
    }

    private func persistToken() {
        Self.persistToken(token, to: tokenFilePath)
    }

    private static func persistToken(_ token: String, to filePath: URL?) {
        guard let filePath else { return }
        do {
            try FileManager.default.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try token.write(to: filePath, atomically: true, encoding: .utf8)
            #if canImport(Darwin)
            _ = chmod(filePath.path, S_IRUSR | S_IWUSR)
            #endif
        } catch {
            NSLog("[WebRemoteAuth] failed to persist token: \(error.localizedDescription)")
        }
    }

    private static func generateToken() -> String {
        "web-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func normalizedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        if let components = URLComponents(string: "ws://\(trimmed)"),
           let host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
           !host.isEmpty {
            return host.lowercased()
        }

        if trimmed.hasPrefix("["),
           let end = trimmed.firstIndex(of: "]") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]).lowercased()
        }

        return trimmed.lowercased()
    }
}
