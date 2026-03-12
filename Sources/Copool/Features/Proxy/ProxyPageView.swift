import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ProxyPageView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutRules.sectionSpacing) {
                proxyHero
                proxyDetailCards
                remoteSection
                cloudflaredSection
            }
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
        .task {
            await model.load()
        }
    }

    private var proxyHero: some View {
        SectionCard(title: L10n.tr("proxy.section.api_proxy")) {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.proxyStatus.running ? Color.mint : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(
                            L10n.tr(
                                "proxy.status_line_format",
                                model.proxyStatus.running ? L10n.tr("proxy.status.running") : L10n.tr("proxy.status.stopped")
                            )
                        )
                    }
                    Spacer(minLength: 0)
                    Text(L10n.tr("proxy.port_line_format", model.proxyStatus.port.map(String.init) ?? "--"))
                    Text(L10n.tr("proxy.available_accounts_format", String(model.proxyStatus.availableAccounts)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    TextField("8787", text: $model.preferredPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button("proxy.action.refresh_status") {
                        Task { await model.refreshStatus() }
                    }
                    .buttonStyle(.frostedCapsule())
                    .disabled(model.loading)

                    Spacer(minLength: 0)

                    if model.proxyStatus.running {
                        Button("proxy.action.stop_api_proxy", role: .destructive) {
                            Task { await model.stopProxy() }
                        }
                        .buttonStyle(.frostedCapsule(prominent: true))
                        .disabled(model.loading)
                    } else {
                        Button("proxy.action.start_api_proxy") {
                            Task { await model.startProxy() }
                        }
                        .buttonStyle(.frostedCapsule(prominent: true))
                        .disabled(model.loading)
                    }
                }

                HStack {
                    Text("proxy.start_on_launch")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { model.autoStartProxy },
                        set: { value in
                            Task { await model.setAutoStartProxy(value) }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    private var proxyDetailCards: some View {
        LazyVStack(spacing: LayoutRules.proxyDetailCardSpacing) {
            detailCard(
                title: L10n.tr("proxy.detail.base_url"),
                value: model.proxyStatus.baseURL ?? L10n.tr("proxy.value.generated_after_start"),
                canCopy: model.proxyStatus.baseURL != nil,
                onCopy: { copyToPasteboard(model.proxyStatus.baseURL) }
            ) {
                EmptyView()
            }

            detailCard(
                title: L10n.tr("proxy.detail.api_key"),
                value: model.proxyStatus.apiKey ?? L10n.tr("proxy.value.generated_after_first_start"),
                canCopy: model.proxyStatus.apiKey != nil,
                onCopy: { copyToPasteboard(model.proxyStatus.apiKey) }
            ) {
                Button("common.refresh") {
                    Task { await model.refreshAPIKey() }
                }
                .buttonStyle(.frostedCapsule())
                .disabled(model.loading)
            }

            infoCard(
                title: L10n.tr("proxy.detail.active_routed_account"),
                headline: model.proxyStatus.activeAccountLabel ?? L10n.tr("proxy.info.no_request_matched"),
                body: model.proxyStatus.activeAccountID ?? L10n.tr("proxy.info.active_account_hint")
            )
            infoCard(title: L10n.tr("proxy.detail.last_error"), headline: model.proxyStatus.lastError ?? L10n.tr("common.none"), body: "")
        }
    }

    private var remoteSection: some View {
        SectionCard(title: L10n.tr("proxy.section.remote_servers")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("proxy.remote.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("proxy.action.add_server") {
                        Task { await model.addRemoteServer() }
                    }
                    .buttonStyle(.frostedCapsule(prominent: true))
                }

                if model.remoteServers.isEmpty {
                    EmptyStateView(
                        title: L10n.tr("proxy.remote.empty.title"),
                        message: L10n.tr("proxy.remote.empty.message")
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.remoteServers) { server in
                            RemoteServerRow(
                                server: server,
                                status: model.remoteStatuses[server.id],
                                logs: model.remoteLogs[server.id],
                                onRefresh: { Task { await model.refreshRemote(server: server) } },
                                onDeploy: { Task { await model.deployRemote(server: server) } },
                                onStart: { Task { await model.startRemote(server: server) } },
                                onStop: { Task { await model.stopRemote(server: server) } },
                                onLogs: { Task { await model.readRemoteLogs(server: server) } }
                            )
                        }
                    }
                }
            }
        }
    }

    private var cloudflaredSection: some View {
        SectionCard(title: L10n.tr("proxy.section.public_access")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("proxy.toggle.enable_public_access", isOn: Binding(
                    get: { model.publicAccessEnabled },
                    set: { value in
                        if value {
                            Task { await model.startCloudflared() }
                        } else {
                            Task { await model.stopCloudflared() }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                HStack(spacing: 8) {
                    Button("common.install") {
                        Task { await model.installCloudflared() }
                    }
                    .buttonStyle(.frostedCapsule())
                    .disabled(model.loading)

                    Button("proxy.action.refresh_status") {
                        Task { await model.refreshCloudflared() }
                    }
                    .buttonStyle(.frostedCapsule())
                }

                TextField(L10n.tr("proxy.field.named_tunnel_hostname_placeholder"), text: $model.cloudflaredHostname)
                    .textFieldStyle(.roundedBorder)

                Toggle("proxy.toggle.use_http2", isOn: $model.cloudflaredUseHTTP2)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(
                    L10n.tr(
                        "proxy.install_status_format",
                        model.cloudflaredStatus.installed ? L10n.tr("proxy.status.installed") : L10n.tr("proxy.status.not_installed")
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    L10n.tr(
                        "proxy.runtime_status_format",
                        model.cloudflaredStatus.running ? L10n.tr("proxy.status.running") : L10n.tr("proxy.status.stopped")
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(L10n.tr("proxy.public_url_format", model.cloudflaredStatus.publicURL ?? "--"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("common.copy") {
                        copyToPasteboard(model.cloudflaredStatus.publicURL)
                    }
                    .buttonStyle(.frostedCapsule())
                    .disabled(model.cloudflaredStatus.publicURL == nil)
                }
            }
        }
    }

    private func detailCard<Trailing: View>(
        title: String,
        value: String,
        canCopy: Bool,
        onCopy: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailing()
                Button("common.copy", action: onCopy)
                    .buttonStyle(.frostedCapsule())
                    .disabled(!canCopy)
            }
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }

    private func infoCard(title: String, headline: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

private struct RemoteServerRow: View {
    let server: RemoteServerConfig
    let status: RemoteProxyStatus?
    let logs: String?
    let onRefresh: () -> Void
    let onDeploy: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(server.label)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(status?.running == true ? L10n.tr("proxy.status.running") : L10n.tr("proxy.status.stopped"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((status?.running == true ? Color.green : Color.gray).opacity(0.2), in: Capsule())
            }

            Text("\(server.sshUser)@\(server.host):\(server.listenPort)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("common.refresh", action: onRefresh)
                Button("common.deploy", action: onDeploy)
                Button("common.start", action: onStart)
                Button("common.stop", role: .destructive, action: onStop)
                Button("common.logs", action: onLogs)
            }
            .buttonStyle(.frostedCapsule())

            if let logs, !logs.isEmpty {
                Text(logs)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .cardSurface(cornerRadius: 8)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .cardSurface(cornerRadius: 10)
    }
}
