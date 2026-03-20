import XCTest
@testable import AIMenu

final class AuthFileRepositoryTests: XCTestCase {
    func testExtractAuthReadsAccountAndClaims() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        let configPath = tempDir.appendingPathComponent("config.toml")
        let paths = FileSystemPaths(
            applicationSupportDirectory: tempDir,
            accountStorePath: tempDir.appendingPathComponent("accounts.json"),
            codexAuthPath: authPath,
            codexConfigPath: configPath,
            proxyDaemonDataDirectory: tempDir.appendingPathComponent("proxyd", isDirectory: true),
            proxyDaemonKeyPath: tempDir.appendingPathComponent("proxyd/api-proxy.key", isDirectory: false),
            cloudflaredLogDirectory: tempDir.appendingPathComponent("cloudflared-logs", isDirectory: true)
        )

        let repository = AuthFileRepository(paths: paths)
        let token = makeJWT(payload: [
            "email": "dev@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_12345",
                "chatgpt_plan_type": "pro",
                "chatgpt_team_name": "Alpha Team"
            ]
        ])

        let auth = JSONValue.object([
            "auth_mode": .string("chatgpt"),
            "tokens": .object([
                "access_token": .string("access-token"),
                "id_token": .string(token)
            ])
        ])

        let extracted = try repository.extractAuth(from: auth)

        XCTAssertEqual(extracted.accountID, "acct_12345")
        XCTAssertEqual(extracted.email, "dev@example.com")
        XCTAssertEqual(extracted.planType, "pro")
        XCTAssertEqual(extracted.teamName, "Alpha Team")
        XCTAssertEqual(extracted.accessToken, "access-token")
    }

    func testExtractAuthPrefersNonPersonalWorkspaceSlug() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        let configPath = tempDir.appendingPathComponent("config.toml")
        let paths = FileSystemPaths(
            applicationSupportDirectory: tempDir,
            accountStorePath: tempDir.appendingPathComponent("accounts.json"),
            codexAuthPath: authPath,
            codexConfigPath: configPath,
            proxyDaemonDataDirectory: tempDir.appendingPathComponent("proxyd", isDirectory: true),
            proxyDaemonKeyPath: tempDir.appendingPathComponent("proxyd/api-proxy.key", isDirectory: false),
            cloudflaredLogDirectory: tempDir.appendingPathComponent("cloudflared-logs", isDirectory: true)
        )

        let repository = AuthFileRepository(paths: paths)
        let token = makeJWT(payload: [
            "email": "dev@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_12345",
                "chatgpt_plan_type": "team",
                "active_organization_id": "org-team",
                "organizations": [
                    [
                        "id": "org-personal",
                        "is_default": true,
                        "title": "Personal",
                        "slug": "personal"
                    ],
                    [
                        "id": "org-team",
                        "is_active": true,
                        "title": "Team Workspace",
                        "slug": "kqikiy"
                    ]
                ]
            ]
        ])

        let auth = JSONValue.object([
            "auth_mode": .string("chatgpt"),
            "tokens": .object([
                "access_token": .string("access-token"),
                "id_token": .string(token)
            ])
        ])

        let extracted = try repository.extractAuth(from: auth)

        XCTAssertEqual(extracted.accountID, "acct_12345")
        XCTAssertEqual(extracted.planType, "team")
        XCTAssertEqual(extracted.teamName, "kqikiy")
    }

    func testMakeChatGPTAuthBuildsCodexCompatibleShape() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        let configPath = tempDir.appendingPathComponent("config.toml")
        let paths = FileSystemPaths(
            applicationSupportDirectory: tempDir,
            accountStorePath: tempDir.appendingPathComponent("accounts.json"),
            codexAuthPath: authPath,
            codexConfigPath: configPath,
            proxyDaemonDataDirectory: tempDir.appendingPathComponent("proxyd", isDirectory: true),
            proxyDaemonKeyPath: tempDir.appendingPathComponent("proxyd/api-proxy.key", isDirectory: false),
            cloudflaredLogDirectory: tempDir.appendingPathComponent("cloudflared-logs", isDirectory: true)
        )

        let repository = AuthFileRepository(paths: paths)
        let idToken = makeJWT(payload: [
            "email": "dev@example.com",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_67890",
                "chatgpt_plan_type": "plus"
            ]
        ])

        let auth = try repository.makeChatGPTAuth(from: ChatGPTOAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: idToken,
            apiKey: "sk-proj-test"
        ))

        XCTAssertEqual(auth["auth_mode"]?.stringValue, "chatgpt")
        XCTAssertEqual(auth["OPENAI_API_KEY"]?.stringValue, "sk-proj-test")
        XCTAssertEqual(auth["tokens"]?["access_token"]?.stringValue, "access-token")
        XCTAssertEqual(auth["tokens"]?["refresh_token"]?.stringValue, "refresh-token")
        XCTAssertEqual(auth["tokens"]?["id_token"]?.stringValue, idToken)
        XCTAssertEqual(auth["tokens"]?["account_id"]?.stringValue, "acct_67890")
        XCTAssertNotNil(auth["last_refresh"]?.stringValue)
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)

        let header = base64URL(headerData)
        let body = base64URL(payloadData)
        return "\(header).\(body)."
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class OpencodeAuthSyncServiceTests: XCTestCase {
    func testSyncFromCodexAuthCreatesBackupWhenOverwritingExistingAuth() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        try writeJSONObject([
            "metadata": ["theme": "dawn"],
            "openai": [
                "type": "oauth",
                "access": "old-access",
                "refresh": "old-refresh",
                "expires": 99
            ]
        ], to: authPath)

        let service = OpencodeAuthSyncService(
            environmentProvider: { ["OPENCODE_AUTH_PATH": authPath.path] },
            nowProvider: { 12_345 }
        )

        try service.syncFromCodexAuth(makeCodexAuthJSON(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            accountID: "acct_1"
        ))

        let updated = try readJSONObject(at: authPath)
        let updatedOpenAI = try XCTUnwrap(updated["openai"] as? [String: Any])
        XCTAssertEqual(updatedOpenAI["access"] as? String, "new-access")
        XCTAssertEqual(updatedOpenAI["refresh"] as? String, "new-refresh")
        XCTAssertEqual(updatedOpenAI["accountId"] as? String, "acct_1")
        XCTAssertEqual(updatedOpenAI["expires"] as? Int64, 3_312_345)
        XCTAssertEqual((updated["metadata"] as? [String: Any])?["theme"] as? String, "dawn")

        let backup = try readJSONObject(at: backupURL(for: authPath))
        let backupOpenAI = try XCTUnwrap(backup["openai"] as? [String: Any])
        XCTAssertEqual(backupOpenAI["access"] as? String, "old-access")
        XCTAssertEqual(backupOpenAI["refresh"] as? String, "old-refresh")
        XCTAssertEqual((backup["metadata"] as? [String: Any])?["theme"] as? String, "dawn")
    }

    func testSyncFromCodexAuthDoesNotCreateBackupOnFirstWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        let service = OpencodeAuthSyncService(
            environmentProvider: { ["OPENCODE_AUTH_PATH": authPath.path] },
            nowProvider: { 1_000 }
        )

        try service.syncFromCodexAuth(makeCodexAuthJSON(
            accessToken: "first-access",
            refreshToken: "first-refresh",
            accountID: "acct_first"
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: authPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL(for: authPath).path))

        let updated = try readJSONObject(at: authPath)
        let updatedOpenAI = try XCTUnwrap(updated["openai"] as? [String: Any])
        XCTAssertEqual(updatedOpenAI["access"] as? String, "first-access")
        XCTAssertEqual(updatedOpenAI["refresh"] as? String, "first-refresh")
        XCTAssertEqual(updatedOpenAI["accountId"] as? String, "acct_first")
    }

    func testSyncFromCodexAuthKeepsOriginalFileWhenWriteFails() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let authPath = tempDir.appendingPathComponent("auth.json")
        try writeJSONObject([
            "openai": [
                "type": "oauth",
                "access": "stable-access",
                "refresh": "stable-refresh",
                "expires": 88
            ]
        ], to: authPath)

        let service = OpencodeAuthSyncService(
            environmentProvider: { ["OPENCODE_AUTH_PATH": authPath.path] },
            nowProvider: { 7_000 },
            dataWriter: { _, _ in
                throw SyncWriteError.simulatedFailure
            }
        )

        XCTAssertThrowsError(try service.syncFromCodexAuth(makeCodexAuthJSON(
            accessToken: "broken-access",
            refreshToken: "broken-refresh",
            accountID: "acct_fail"
        ))) { error in
            guard case let AppError.io(message) = error else {
                return XCTFail("Expected AppError.io, got \(error)")
            }
            XCTAssertTrue(message.contains(authPath.path))
        }

        let current = try readJSONObject(at: authPath)
        let currentOpenAI = try XCTUnwrap(current["openai"] as? [String: Any])
        XCTAssertEqual(currentOpenAI["access"] as? String, "stable-access")
        XCTAssertEqual(currentOpenAI["refresh"] as? String, "stable-refresh")

        let backup = try readJSONObject(at: backupURL(for: authPath))
        let backupOpenAI = try XCTUnwrap(backup["openai"] as? [String: Any])
        XCTAssertEqual(backupOpenAI["access"] as? String, "stable-access")
        XCTAssertEqual(backupOpenAI["refresh"] as? String, "stable-refresh")
    }

    private func makeCodexAuthJSON(accessToken: String, refreshToken: String, accountID: String) -> JSONValue {
        .object([
            "tokens": .object([
                "access_token": .string(accessToken),
                "refresh_token": .string(refreshToken),
                "account_id": .string(accountID)
            ])
        ])
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bak")
    }
}

private enum SyncWriteError: Error {
    case simulatedFailure
}
