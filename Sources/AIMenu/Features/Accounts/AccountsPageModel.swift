import Foundation
import Combine

@MainActor
final class AccountsPageModel: ObservableObject {
    private let coordinator: AccountsCoordinator
    private let manualRefreshService: AccountsManualRefreshServiceProtocol?
    private let onLocalAccountsChanged: (([AccountSummary]) -> Void)?
    private let noticeScheduler = NoticeAutoDismissScheduler()
    private var hasLoaded = false

    @Published var state: ViewState<[AccountSummary]>
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }
    @Published var isRefreshing = false
    @Published var isImporting = false
    @Published var isAdding = false
    @Published private(set) var collapsedAccountIDs: Set<String> = []

    init(
        coordinator: AccountsCoordinator,
        manualRefreshService: AccountsManualRefreshServiceProtocol? = nil,
        onLocalAccountsChanged: (([AccountSummary]) -> Void)? = nil,
        initialAccounts: [AccountSummary]? = nil
    ) {
        self.coordinator = coordinator
        self.manualRefreshService = manualRefreshService
        self.onLocalAccountsChanged = onLocalAccountsChanged
        self.state = initialAccounts.map { initialAccounts in
            Self.makeViewState(accounts: initialAccounts)
        } ?? .loading
    }

    func loadIfNeeded() async {
        if !hasLoaded {
            await load()
        }
    }

    func load() async {
        do {
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            hasLoaded = true
        } catch {
            state = .error(message: error.localizedDescription)
            hasLoaded = true
        }
    }

    func importCurrentAuth() async {
        isImporting = true
        defer { isImporting = false }

        do {
            let imported = try await coordinator.importCurrentAuthAccount(customLabel: nil)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_format", imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addAccountViaLogin() async {
        isAdding = true
        defer { isAdding = false }

        do {
            let imported = try await coordinator.addAccountViaLogin(customLabel: nil)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.imported_new_format", imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importAuthDocument(from url: URL, setAsCurrent: Bool) async {
        if setAsCurrent {
            isImporting = true
        } else {
            isAdding = true
        }
        defer {
            if setAsCurrent {
                isImporting = false
            } else {
                isAdding = false
            }
        }

        do {
            let imported = try await coordinator.importAccountFile(
                from: url,
                customLabel: nil,
                setAsCurrent: setAsCurrent
            )
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            let key = setAsCurrent
                ? "accounts.notice.imported_format"
                : "accounts.notice.imported_new_format"
            notice = NoticeMessage(style: .success, text: L10n.tr(key, imported.label))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importMultipleAuthDocuments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }

        var successCount = 0
        var lastError: String?

        for url in urls {
            do {
                _ = try await coordinator.importAccountFile(
                    from: url,
                    customLabel: nil,
                    setAsCurrent: false
                )
                successCount += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        do {
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
        } catch {
            // ignore list error
        }

        if successCount > 0 {
            let msg = "Imported \(successCount) account\(successCount > 1 ? "s" : "")"
            if let lastError {
                notice = NoticeMessage(style: .error, text: "\(msg), but some failed: \(lastError)")
            } else {
                notice = NoticeMessage(style: .success, text: msg)
            }
        } else if let lastError {
            notice = NoticeMessage(style: .error, text: lastError)
        }
    }

    func reportImportSelectionFailure(_ error: Error) {
        notice = NoticeMessage(style: .error, text: error.localizedDescription)
    }

    func refreshUsage() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let accounts: [AccountSummary]
            if let manualRefreshService {
                accounts = try await manualRefreshService.performManualRefresh()
            } else {
                accounts = try await coordinator.refreshAllUsage(force: true)
            }
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            let noticeKey = manualRefreshService == nil
                ? "accounts.notice.usage_refreshed"
                : "accounts.notice.accounts_refreshed"
            notice = NoticeMessage(style: .info, text: L10n.tr(noticeKey))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteAccount(id: String) async {
        do {
            try await coordinator.deleteAccount(id: id)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            notice = NoticeMessage(style: .info, text: L10n.tr("accounts.notice.account_deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveTeamAlias(id: String, alias: String?) async {
        do {
            _ = try await coordinator.updateTeamAlias(id: id, alias: alias)
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            publishLocalAccounts(accounts)
            notice = NoticeMessage(style: .success, text: L10n.tr("accounts.notice.team_name_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func isAccountCollapsed(_ id: String) -> Bool {
        collapsedAccountIDs.contains(id)
    }

    var areAllAccountsCollapsed: Bool {
        guard case .content(let accounts) = state else { return false }
        let ids = Set(accounts.map(\.id))
        guard !ids.isEmpty else { return false }
        return collapsedAccountIDs.isSuperset(of: ids)
    }

    var canImportCurrentAuthAction: Bool {
        !isImporting && !isAdding
    }

    var canAddAccountAction: Bool {
        !isImporting && !isAdding
    }

    var canRefreshUsageAction: Bool {
        !isRefreshing && !isAdding
    }

    func toggleAllAccountsCollapsed() {
        guard case .content(let accounts) = state else { return }
        let ids = Set(accounts.map(\.id))
        guard !ids.isEmpty else {
            collapsedAccountIDs = []
            return
        }
        collapsedAccountIDs = collapsedAccountIDs.isSuperset(of: ids) ? [] : ids
    }

    var hasResolvedInitialState: Bool {
        if case .loading = state {
            return false
        }
        return true
    }

    func resetStuckStatesIfNeeded() {
        if isImporting { isImporting = false }
        if isAdding { isAdding = false }
    }

    func syncFromBackgroundRefresh(_ accounts: [AccountSummary]) {
        applyAccounts(accounts)
    }

    static func makeViewState(accounts: [AccountSummary]) -> ViewState<[AccountSummary]> {
        let sorted = AccountRanking.sortByRemaining(accounts)
        if sorted.isEmpty {
            return .empty(message: L10n.tr("accounts.empty.message.no_accounts"))
        }
        return .content(sorted)
    }

    private func applyAccounts(_ accounts: [AccountSummary]) {
        let sorted = AccountRanking.sortByRemaining(accounts)
        let availableIDs = Set(sorted.map(\.id))
        let nextCollapsed = collapsedAccountIDs.intersection(availableIDs)
        if nextCollapsed != collapsedAccountIDs {
            collapsedAccountIDs = nextCollapsed
        }

        let nextState = AccountsPageModel.makeViewState(accounts: sorted)
        if state != nextState {
            state = nextState
        }
    }

    private func publishLocalAccounts(_ accounts: [AccountSummary]) {
        onLocalAccountsChanged?(AccountRanking.sortByRemaining(accounts))
    }
}
