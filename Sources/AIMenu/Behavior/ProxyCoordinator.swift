import Foundation
import Combine

actor ProxyCoordinator {
    private let proxyService: ProxyRuntimeService
    private let cloudflaredService: CloudflaredServiceProtocol
    private let providerCoordinator: ProviderCoordinator

    init(
        proxyService: ProxyRuntimeService,
        cloudflaredService: CloudflaredServiceProtocol,
        providerCoordinator: ProviderCoordinator
    ) {
        self.proxyService = proxyService
        self.cloudflaredService = cloudflaredService
        self.providerCoordinator = providerCoordinator
    }

    func loadStatus() async -> (ApiProxyStatus, CloudflaredStatus) {
        async let proxy = proxyService.status()
        async let cloudflared = cloudflaredService.status()
        let syncedProxy = await syncManagedCodexProxyProviderIfNeeded(await proxy)
        return (syncedProxy, await cloudflared)
    }

    func startProxy(preferredPort: Int?) async throws -> ApiProxyStatus {
        try await proxyService.syncAccountsStore()
        let status = try await proxyService.start(preferredPort: preferredPort)
        return await syncManagedCodexProxyProviderIfNeeded(status)
    }

    func stopProxy() async -> ApiProxyStatus {
        await proxyService.stop()
    }

    func refreshAPIKey() async throws -> ApiProxyStatus {
        let status = try await proxyService.refreshAPIKey()
        return await syncManagedCodexProxyProviderIfNeeded(status)
    }

    func installCloudflared() async throws -> CloudflaredStatus {
        try await cloudflaredService.install()
    }

    func startCloudflared(input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus {
        try await cloudflaredService.start(input)
    }

    func stopCloudflared() async -> CloudflaredStatus {
        await cloudflaredService.stop()
    }

    func refreshCloudflared() async -> CloudflaredStatus {
        await cloudflaredService.status()
    }

    private func syncManagedCodexProxyProviderIfNeeded(_ status: ApiProxyStatus) async -> ApiProxyStatus {
        guard status.running else { return status }

        do {
            _ = try await providerCoordinator.upsertManagedCodexProxyProvider(from: status)
            return status
        } catch {
            var updated = status
            let syncMessage = L10n.tr(
                "error.proxy.codex_provider_sync_failed_format",
                error.localizedDescription
            )
            if let existing = updated.lastError?.trimmedNonEmpty {
                updated.lastError = "\(existing) | \(syncMessage)"
            } else {
                updated.lastError = syncMessage
            }
            return updated
        }
    }
}
