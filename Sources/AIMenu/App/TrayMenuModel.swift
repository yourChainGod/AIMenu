import Foundation
import Combine

@MainActor
final class TrayMenuModel: ObservableObject, AccountsManualRefreshServiceProtocol {
    private let accountsCoordinator: AccountsCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private var refreshTask: Task<Void, Never>?

    @Published var accounts: [AccountSummary] = []
    @Published var notice: String?

    init(
        accountsCoordinator: AccountsCoordinator,
        settingsCoordinator: SettingsCoordinator,
        initialAccounts: [AccountSummary] = []
    ) {
        self.accountsCoordinator = accountsCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.accounts = initialAccounts
    }

    func startBackgroundRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            await self.refreshNow(forceUsageRefresh: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self.refreshNow(forceUsageRefresh: true)
            }
        }
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit {
        refreshTask?.cancel()
    }

    func refreshNow(forceUsageRefresh: Bool) async {
        do {
            let latestAccounts = try await executeRefresh(forceUsageRefresh: forceUsageRefresh)
            accounts = latestAccounts
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func performManualRefresh() async throws -> [AccountSummary] {
        let settings = try await settingsCoordinator.currentSettings()
        applySettings(settings)

        let latestAccounts = try await refreshLocalAccounts(
            forceUsageRefresh: true,
            bypassUsageThrottle: true
        )

        accounts = latestAccounts
        notice = nil
        return latestAccounts
    }

    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary]) {
        self.accounts = accounts
    }

    func applySettings(_ settings: AppSettings) {
        _ = settings
    }

    var title: String {
        let focusAccount = accounts.first(where: { $0.isCurrent }) ?? AccountRanking.sortByRemaining(accounts).first
        guard let focusAccount else {
            return L10n.tr("tray.title.placeholder")
        }

        let five = percent(remainingValue(window: focusAccount.usage?.fiveHour))
        let week = percent(remainingValue(window: focusAccount.usage?.oneWeek))
        return L10n.tr("tray.title.format", five, week)
    }

    func accountLine(_ account: AccountSummary) -> String {
        let prefix = account.isCurrent ? L10n.tr("tray.account.current_prefix") : ""
        let five = percent(remainingValue(window: account.usage?.fiveHour))
        let week = percent(remainingValue(window: account.usage?.oneWeek))
        return L10n.tr("tray.account.line.format", prefix, account.label, five, week)
    }

    private func remainingValue(window: UsageWindow?) -> Double? {
        guard let window else { return nil }
        return max(0, 100 - window.usedPercent)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func executeRefresh(forceUsageRefresh: Bool) async throws -> [AccountSummary] {
        let settings = try await settingsCoordinator.currentSettings()
        applySettings(settings)

        return try await refreshLocalAccounts(
            forceUsageRefresh: forceUsageRefresh,
            bypassUsageThrottle: false
        )
    }

    private func refreshLocalAccounts(
        forceUsageRefresh: Bool,
        bypassUsageThrottle: Bool
    ) async throws -> [AccountSummary] {
        if forceUsageRefresh {
            _ = try await accountsCoordinator.refreshAllUsage(force: bypassUsageThrottle)
        }
        return try await accountsCoordinator.listAccounts()
    }
}
