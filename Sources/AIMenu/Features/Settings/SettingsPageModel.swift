import Foundation
import Combine

@MainActor
final class SettingsPageModel: ObservableObject {
    private let settingsCoordinator: SettingsCoordinator
    private let editorAppService: EditorAppServiceProtocol
    private let onSettingsUpdated: @MainActor (AppSettings) -> Void
    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var settings: AppSettings = .defaultValue
    @Published var installedEditorApps: [InstalledEditorApp] = []
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }
    private var hasLoaded = false

    init(
        settingsCoordinator: SettingsCoordinator,
        editorAppService: EditorAppServiceProtocol,
        onSettingsUpdated: @escaping @MainActor (AppSettings) -> Void = { _ in }
    ) {
        self.settingsCoordinator = settingsCoordinator
        self.editorAppService = editorAppService
        self.onSettingsUpdated = onSettingsUpdated
    }

    func loadIfNeeded() async {
        if !hasLoaded {
            await load()
        }
    }

    func load() async {
        do {
            settings = try await settingsCoordinator.currentSettings()
            installedEditorApps = editorAppService.listInstalledApps()
            onSettingsUpdated(settings)
            hasLoaded = true
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func setLaunchAtStartup(_ value: Bool) {
        Task { await update(AppSettingsPatch(launchAtStartup: value)) }
    }

    func setLaunchAfterSwitch(_ value: Bool) {
        Task { await update(AppSettingsPatch(launchCodexAfterSwitch: value)) }
    }

    func setAutoSmartSwitch(_ value: Bool) {
        Task { await update(AppSettingsPatch(autoSmartSwitch: value)) }
    }

    func setAutoStartProxy(_ value: Bool) {
        Task { await update(AppSettingsPatch(autoStartApiProxy: value)) }
    }

    func setLocale(_ value: String) {
        Task { await update(AppSettingsPatch(locale: value)) }
    }

    func setSyncOpencodeOpenaiAuth(_ value: Bool) {
        Task { await update(AppSettingsPatch(syncOpencodeOpenaiAuth: value)) }
    }

    func setRestartEditorsOnSwitch(_ value: Bool) {
        guard value else {
            Task { await update(AppSettingsPatch(restartEditorsOnSwitch: false)) }
            return
        }

        guard let target = resolvedRestartEditorTarget else {
            notice = NoticeMessage(style: .error, text: L10n.tr("error.editor.no_restart_target_selected"))
            return
        }

        Task {
            await update(
                AppSettingsPatch(
                    restartEditorsOnSwitch: true,
                    restartEditorTargets: [target]
                )
            )
        }
    }

    func setRestartEditorTarget(_ target: EditorAppID?) {
        guard let resolvedTarget = target ?? resolvedRestartEditorTarget else {
            notice = NoticeMessage(style: .error, text: L10n.tr("error.editor.no_restart_target_selected"))
            return
        }

        Task {
            await update(
                AppSettingsPatch(restartEditorTargets: [resolvedTarget]),
                successText: L10n.tr("settings.notice.restart_target_updated")
            )
        }
    }

    private var resolvedRestartEditorTarget: EditorAppID? {
        if let stored = settings.restartEditorTargets.first,
           installedEditorApps.contains(where: { $0.id == stored }) {
            return stored
        }
        return installedEditorApps.first?.id
    }

    private func update(_ patch: AppSettingsPatch, successText: String = L10n.tr("settings.notice.updated")) async {
        do {
            settings = try await settingsCoordinator.updateSettings(patch)
            onSettingsUpdated(settings)
            notice = NoticeMessage(style: .success, text: successText)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
