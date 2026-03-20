import Foundation
import Combine

@MainActor
final class ProviderPageModel: ObservableObject {
    private let coordinator: ProviderCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var selectedApp: ProviderAppType = .claude
    @Published var providers: [Provider] = []
    @Published var speedTestResults: [String: SpeedTestResult] = [:]
    @Published var loading = false
    @Published var isAddingProvider = false
    @Published var editingProvider: Provider?
    @Published var notice: NoticeMessage? {
        didSet { noticeScheduler.schedule(notice) { [weak self] in self?.notice = nil } }
    }

    init(coordinator: ProviderCoordinator) {
        self.coordinator = coordinator
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            providers = try await coordinator.listProviders(for: selectedApp)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchApp(_ app: ProviderAppType) async {
        selectedApp = app
        await load()
    }

    func addProvider(draft: ProviderDraft) async {
        let provider = draft.makeProvider()
        do {
            let outcome = try await coordinator.addProvider(provider)
            await load()
            isAddingProvider = false
            notice = NoticeMessage(
                style: .success,
                text: outcome.didApplyToLiveConfig
                    ? L10n.tr("providers.notice.added_enabled_format", outcome.provider.name)
                    : L10n.tr("providers.notice.added_format", outcome.provider.name)
            )
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchProvider(_ provider: Provider) async {
        do {
            try await coordinator.switchProvider(id: provider.id, appType: selectedApp)
            await load()
            notice = NoticeMessage(style: .success, text: L10n.tr("providers.notice.switched_format", provider.name))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteProvider(_ provider: Provider) async {
        do {
            let outcome = try await coordinator.deleteProvider(id: provider.id, appType: selectedApp)
            await load()
            if outcome.didDeleteCurrentProvider, let fallback = outcome.fallbackProvider {
                notice = NoticeMessage(
                    style: .info,
                    text: L10n.tr("providers.notice.deleted_switched_format", provider.name, fallback.name)
                )
            } else if outcome.didDeleteCurrentProvider {
                notice = NoticeMessage(style: .info, text: L10n.tr("providers.notice.deleted_cleared_format", provider.name))
            } else {
                notice = NoticeMessage(style: .info, text: L10n.tr("providers.notice.deleted_format", provider.name))
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func speedTestAll() async {
        for provider in providers {
            let result = await coordinator.testSpeed(for: provider)
            speedTestResults[provider.id] = result
        }
    }

    func updateProvider(_ provider: Provider) async {
        do {
            let outcome = try await coordinator.updateProvider(provider)
            editingProvider = nil
            await load()
            notice = NoticeMessage(
                style: .success,
                text: outcome.didApplyToLiveConfig
                    ? L10n.tr("providers.notice.saved_synced_format", outcome.provider.name)
                    : L10n.tr("providers.notice.saved_format", outcome.provider.name)
            )
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func speedTest(_ provider: Provider) async {
        let result = await coordinator.testSpeed(for: provider)
        speedTestResults[provider.id] = result
    }
}
