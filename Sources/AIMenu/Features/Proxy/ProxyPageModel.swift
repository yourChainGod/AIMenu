import Foundation
import Combine

@MainActor
final class ProxyPageModel: ObservableObject {
    private let coordinator: ProxyCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()
    private var didRunLaunchBootstrap = false

    @Published var proxyStatus: ApiProxyStatus = .idle
    @Published var cloudflaredStatus: CloudflaredStatus = .idle

    @Published var preferredPortText = "8787"
    @Published var cloudflaredTunnelMode: CloudflaredTunnelMode = .quick
    @Published var cloudflaredNamedInput = NamedCloudflaredTunnelInput(
        apiToken: "",
        accountID: "",
        zoneID: "",
        hostname: ""
    )
    @Published var cloudflaredUseHTTP2 = false
    @Published var autoStartProxy = false
    @Published var publicAccessEnabled = false
    @Published var apiProxySectionExpanded = false
    @Published var cloudflaredSectionExpanded = false

    @Published var loading = false
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    init(
        coordinator: ProxyCoordinator,
        settingsCoordinator: SettingsCoordinator
    ) {
        self.coordinator = coordinator
        self.settingsCoordinator = settingsCoordinator
    }

    var cloudflaredExpanded: Bool { cloudflaredSectionExpanded }

    var canStartCloudflared: Bool {
        guard !loading else { return false }
        guard proxyStatus.running, proxyStatus.port != nil else { return false }
        guard cloudflaredStatus.installed, !cloudflaredStatus.running else { return false }
        return cloudflaredTunnelMode == .quick || cloudflaredNamedInputReady
    }

    var canEditCloudflaredInput: Bool { !loading && !cloudflaredStatus.running }

    var cloudflaredNamedInputReady: Bool {
        !cloudflaredNamedInput.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.zoneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !cloudflaredNamedInput.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bootstrapOnAppLaunch(using settings: AppSettings) async {
        guard !didRunLaunchBootstrap else { return }
        didRunLaunchBootstrap = true
        autoStartProxy = settings.autoStartApiProxy
        await refreshStatusOnly()
        guard settings.autoStartApiProxy, !proxyStatus.running else { return }
        do {
            proxyStatus = try await coordinator.startProxy(preferredPort: nil)
            await refreshStatusOnly()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshForTabEntry() async { await refreshStatusOnly() }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let settings = try await settingsCoordinator.currentSettings()
            autoStartProxy = settings.autoStartApiProxy
            await refreshStatusOnly()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshStatus() async {
        loading = true
        defer { loading = false }
        await refreshStatusOnly()
    }

    func startProxy() async {
        loading = true
        defer { loading = false }
        do {
            proxyStatus = try await coordinator.startProxy(preferredPort: Int(preferredPortText))
            await refreshStatusOnly()
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.api_proxy_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopProxy() async {
        loading = true
        defer { loading = false }
        proxyStatus = await coordinator.stopProxy()
        await refreshStatusOnly()
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.api_proxy_stopped"))
    }

    func refreshAPIKey() async {
        loading = true
        defer { loading = false }
        do {
            proxyStatus = try await coordinator.refreshAPIKey()
            await refreshStatusOnly()
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.api_key_refreshed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func installCloudflared() async {
        loading = true
        defer { loading = false }
        do {
            applyCloudflaredStatus(try await coordinator.installCloudflared())
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_installed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startCloudflared() async {
        loading = true
        defer { loading = false }
        do {
            let input = try buildCloudflaredStartInput()
            applyCloudflaredStatus(try await coordinator.startCloudflared(input: input))
            publicAccessEnabled = true
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.cloudflared_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopCloudflared() async {
        loading = true
        defer { loading = false }
        applyCloudflaredStatus(await coordinator.stopCloudflared())
        notice = NoticeMessage(style: .info, text: L10n.tr("proxy.notice.cloudflared_stopped"))
    }

    func refreshCloudflared() async {
        applyCloudflaredStatus(await coordinator.refreshCloudflared())
    }

    func setPublicAccessEnabled(_ enabled: Bool) async {
        if enabled {
            publicAccessEnabled = true
            cloudflaredSectionExpanded = true
        } else {
            publicAccessEnabled = false
            guard cloudflaredStatus.running else { return }
            await stopCloudflared()
        }
    }

    func setAutoStartProxy(_ value: Bool) async {
        do {
            let updated = try await settingsCoordinator.updateSettings(AppSettingsPatch(autoStartApiProxy: value))
            autoStartProxy = updated.autoStartApiProxy
            notice = NoticeMessage(style: .success, text: L10n.tr("proxy.notice.auto_start_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func refreshStatusOnly() async {
        let pair = await coordinator.loadStatus()
        proxyStatus = pair.0
        applyCloudflaredStatus(pair.1)
    }

    private func applyCloudflaredStatus(_ status: CloudflaredStatus) {
        cloudflaredStatus = status
        cloudflaredUseHTTP2 = status.useHTTP2
        if let mode = status.tunnelMode { cloudflaredTunnelMode = mode }
        if let hostname = status.customHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hostname.isEmpty { cloudflaredNamedInput.hostname = hostname }
        if status.running {
            publicAccessEnabled = true
            cloudflaredSectionExpanded = true
        }
    }

    private func buildCloudflaredStartInput() throws -> StartCloudflaredTunnelInput {
        guard let port = proxyStatus.port else {
            throw AppError.invalidData(L10n.tr("proxy.notice.start_api_proxy_first"))
        }
        return StartCloudflaredTunnelInput(
            apiProxyPort: port,
            useHTTP2: cloudflaredUseHTTP2,
            mode: cloudflaredTunnelMode,
            named: cloudflaredTunnelMode == .named ? try normalizedNamedInput() : nil
        )
    }

    private func normalizedNamedInput() throws -> NamedCloudflaredTunnelInput {
        let apiToken = cloudflaredNamedInput.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = cloudflaredNamedInput.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let zoneID = cloudflaredNamedInput.zoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostname = cloudflaredNamedInput.hostname
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !apiToken.isEmpty, !accountID.isEmpty, !zoneID.isEmpty, !hostname.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.cloudflared.named_required_fields"))
        }
        guard hostname.contains(".") else {
            throw AppError.invalidData(L10n.tr("error.cloudflared.named_invalid_hostname"))
        }
        return NamedCloudflaredTunnelInput(apiToken: apiToken, accountID: accountID, zoneID: zoneID, hostname: hostname)
    }
}
