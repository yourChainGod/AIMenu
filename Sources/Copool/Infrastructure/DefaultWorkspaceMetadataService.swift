import Foundation

final class DefaultWorkspaceMetadataService: WorkspaceMetadataService, @unchecked Sendable {
    private let session: URLSession
    private let configPath: URL

    init(session: URLSession = .shared, configPath: URL) {
        self.session = session
        self.configPath = configPath
    }

    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata] {
        var errors: [String] = []

        for url in resolveAccountURLs() {
            guard let endpoint = URL(string: url) else { continue }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 18
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    errors.append("\(url) -> \(L10n.tr("error.usage.invalid_response"))")
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let snippet = String(body.prefix(140))
                    errors.append("\(url) -> \(httpResponse.statusCode): \(snippet)")
                    continue
                }

                let decoder = JSONDecoder()
                let payload = try decoder.decode(WorkspaceAccountsResponse.self, from: data)
                return payload.items.map {
                    WorkspaceMetadata(
                        accountID: $0.id,
                        workspaceName: $0.name,
                        structure: $0.structure
                    )
                }
            } catch {
                errors.append("\(url) -> \(error.localizedDescription)")
            }
        }

        let preview = errors.prefix(2).joined(separator: " | ")
        if errors.count > 2 {
            throw AppError.network(L10n.tr("error.usage.request_failed_with_more_format", preview, String(errors.count - 2)))
        }
        throw AppError.network(L10n.tr("error.usage.request_failed_format", preview))
    }

    private func resolveAccountURLs() -> [String] {
        let baseOrigin = ChatGPTBaseOriginResolver.resolve(configPath: configPath)
        let backendPrefix = "/backend-api"

        var candidates: [String] = []
        if let originWithoutBackend = baseOrigin.removingSuffix(backendPrefix) {
            candidates.append("\(baseOrigin)/accounts")
            candidates.append("\(originWithoutBackend)\(backendPrefix)/accounts")
        } else {
            candidates.append("\(baseOrigin)\(backendPrefix)/accounts")
            candidates.append("\(baseOrigin)/accounts")
        }

        candidates.append("https://chatgpt.com/backend-api/accounts")

        var deduped: [String] = []
        for candidate in candidates where !deduped.contains(candidate) {
            deduped.append(candidate)
        }
        return deduped
    }
}

private struct WorkspaceAccountsResponse: Decodable {
    var items: [WorkspaceAccountItem]
}

private struct WorkspaceAccountItem: Decodable {
    var id: String
    var name: String?
    var structure: String?
}

private extension String {
    func removingSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }
}
