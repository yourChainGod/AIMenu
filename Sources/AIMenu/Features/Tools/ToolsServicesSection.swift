import SwiftUI
import AppKit

struct ToolsServicesSection: View {
    @ObservedObject var model: ToolsPageModel
    @State private var forceKillPort: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing12) {
            webRemoteServiceCard
            cursor2APIServiceCard
            portToolsCard
        }
        .confirmationDialog(
            L10n.tr("tools.services.action.force_confirm_title"),
            isPresented: Binding(get: { forceKillPort != nil }, set: { if !$0 { forceKillPort = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("tools.services.action.force"), role: .destructive) {
                guard let port = forceKillPort else { return }
                Task { await model.releaseTrackedPort(port, force: true) }
            }
        } message: {
            if let port = forceKillPort {
                Text(L10n.tr("tools.services.action.force_confirm_message_format", String(port)))
            }
        }
    }

    // MARK: - Web Remote

    private var webRemoteServiceCard: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing8) {
            // Header
            HStack(alignment: .center, spacing: LayoutRules.spacing8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cyan.opacity(OpacityScale.muted))
                        .frame(width: 28, height: 28)
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(.cyan)
                }

                Text(L10n.tr("tools.services.web_remote.title"))
                    .font(.subheadline.weight(.semibold))

                UnifiedBadge(
                    text: model.webRemoteStatus.running ? L10n.tr("web_remote.status.running") : L10n.tr("web_remote.status.stopped"),
                    tint: model.webRemoteStatus.running ? Color.cyan : Color.secondary
                )

                Spacer(minLength: 0)

                Button {
                    Task { await model.refreshWebRemoteStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .aimenuActionButtonStyle(density: .compact)
                .help(L10n.tr("web_remote.action.refresh_status"))
            }

            // Port + Clients info
            if model.webRemoteStatus.running {
                let reachableURLs = model.webRemoteReachableURLs

                HStack(spacing: LayoutRules.spacing6) {
                    compactMetric(label: L10n.tr("tools.services.metric.http"), value: "\(model.webRemoteStatus.httpPort ?? 0)", tint: .cyan)
                    compactMetric(label: L10n.tr("tools.services.metric.ws"), value: "\(model.webRemoteStatus.wsPort ?? 0)", tint: .cyan)
                    compactMetric(label: L10n.tr("web_remote.label.clients"), value: "\(model.webRemoteStatus.connectedClients)", tint: .secondary)
                }

                // Token display + copy
                HStack(spacing: 4) {
                    Text(model.webRemoteToken)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    CopyButton(text: model.webRemoteToken)
                    Button(L10n.tr("web_remote.action.refresh_token")) {
                        Task { await model.refreshWebRemoteToken() }
                    }
                    .aimenuActionButtonStyle(density: .compact)
                }

                if !reachableURLs.isEmpty {
                    VStack(alignment: .leading, spacing: LayoutRules.spacing6) {
                        Text(L10n.tr("web_remote.label.access_urls"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(reachableURLs) { target in
                            HStack(spacing: LayoutRules.spacing6) {
                                UnifiedBadge(
                                    text: target.label,
                                    tint: target.isLAN ? .mint : .secondary,
                                    density: .compact
                                )

                                Text(target.displayURL)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)

                                Spacer(minLength: 0)

                                Button(L10n.tr("web_remote.action.open_url")) {
                                    model.openWebRemoteURL(target.browserURL)
                                }
                                .aimenuActionButtonStyle(density: .compact)

                                CopyButton(text: target.browserURL)
                            }
                        }

                        if reachableURLs.contains(where: \.isLAN) {
                            Text(L10n.tr("web_remote.description.lan_hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: LayoutRules.spacing6) {
                    Button(L10n.tr("web_remote.action.open_url")) {
                        model.openWebRemoteURL()
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .cyan, density: .compact)

                    Button(L10n.tr("web_remote.action.copy_url")) {
                        model.copyWebRemoteURL()
                    }
                    .aimenuActionButtonStyle(density: .compact)

                    Spacer(minLength: 0)
                }
            } else {
                // Port inputs (editable when stopped)
                HStack(spacing: LayoutRules.spacing6) {
                    HStack(spacing: 4) {
                        Text(L10n.tr("tools.services.metric.http"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("9090", text: $model.webRemoteHTTPPortText)
                            .font(.caption2.monospaced())
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 4) {
                        Text(L10n.tr("tools.services.metric.ws"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("9091", text: $model.webRemoteWSPortText)
                            .font(.caption2.monospaced())
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let error = model.webRemoteStatus.lastError?.trimmedNonEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Action buttons
            HStack(spacing: LayoutRules.spacing6) {
                if model.webRemoteStatus.running {
                    Button(L10n.tr("web_remote.action.stop")) {
                        Task { await model.stopWebRemote() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .red, density: .compact)
                    .disabled(model.loading)
                } else {
                    Button(L10n.tr("web_remote.action.start")) {
                        Task { await model.startWebRemote() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .cyan, density: .compact)
                    .disabled(model.loading)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(LayoutRules.spacing10)
        .cardSurface(cornerRadius: LayoutRules.radiusCard, tint: Color.cyan.opacity(OpacityScale.faint))
    }

    // MARK: - Cursor2API

    private var cursor2APIServiceCard: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing8) {
            // Header row: icon + title + badge + refresh button
            HStack(alignment: .center, spacing: LayoutRules.spacing8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(OpacityScale.muted))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                }

                Text(L10n.tr("tools.services.cursor2api.title"))
                    .font(.subheadline.weight(.semibold))

                UnifiedBadge(
                    text: model.cursor2APIStatus.running
                        ? L10n.tr("tools.services.cursor2api.status.running")
                        : (model.cursor2APIStatus.installed
                            ? L10n.tr("tools.services.cursor2api.status.installed")
                            : L10n.tr("tools.services.cursor2api.status.not_installed")),
                    tint: model.cursor2APIStatus.running ? Color.mint : Color.secondary
                )

                Spacer(minLength: 0)

                Button {
                    Task { await model.refreshManagedToolStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .aimenuActionButtonStyle(density: .compact)
                .help(L10n.tr("tools.services.action.refresh_service_status"))
            }

            // Compact info strip: port + API key + model in a single row
            HStack(spacing: LayoutRules.spacing6) {
                compactMetric(label: L10n.tr("tools.services.metric.port"), value: "\(model.cursor2APIStatus.port)", tint: .blue)
                compactMetric(label: L10n.tr("tools.services.metric.api_key"), value: ToolsHelpers.maskedSecret(model.cursor2APIStatus.apiKey), tint: .mint)
                compactMetric(
                    label: L10n.tr("tools.services.metric.model"),
                    value: model.cursor2APIStatus.models.first ?? "claude-sonnet-4.6",
                    tint: .secondary
                )
            }

            if let error = model.cursor2APIStatus.lastError?.trimmedNonEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Action buttons row
            HStack(spacing: LayoutRules.spacing6) {
                Button(model.cursor2APIStatus.installed ? L10n.tr("tools.services.action.reinstall") : L10n.tr("tools.services.action.install")) {
                    Task { await model.installCursor2API() }
                }
                .aimenuActionButtonStyle(density: .compact)

                if model.cursor2APIStatus.running {
                    Button(L10n.tr("common.action.stop")) {
                        Task { await model.stopCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .red, density: .compact)
                } else {
                    Button(L10n.tr("common.action.start")) {
                        Task { await model.startCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                    .disabled(!model.cursor2APIStatus.installed)
                }

                Button(L10n.tr("tools.services.action.apply_to_claude")) {
                    Task { await model.applyCursor2APIToClaude() }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .mint, density: .compact)
                .disabled(!model.cursor2APIStatus.running)

                Spacer(minLength: 0)

                if model.cursor2APIStatus.logPath != nil {
                    Button {
                        if let logPath = model.cursor2APIStatus.logPath {
                            NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
                        }
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.caption2.weight(.bold))
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .help(L10n.tr("tools.services.action.view_log"))
                }

                if model.cursor2APIStatus.configPath != nil {
                    Button {
                        if let configPath = model.cursor2APIStatus.configPath {
                            NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.caption2.weight(.bold))
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .help(L10n.tr("tools.services.action.view_config"))
                }
            }
        }
        .padding(LayoutRules.spacing10)
        .cardSurface(cornerRadius: LayoutRules.radiusCard, tint: Color.blue.opacity(OpacityScale.faint))
    }

    /// Compact inline metric chip — single-line label:value
    private func compactMetric(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: LayoutRules.radiusTiny, style: .continuous)
                .fill((tint == .secondary ? Color.primary : tint).opacity(OpacityScale.subtle))
        )
    }

    // MARK: - Port Management

    private var portToolsCard: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing8) {
            // Header with inline port input
            HStack(spacing: LayoutRules.spacing8) {
                Label(L10n.tr("tools.services.port_management.title"), systemImage: "wave.3.right")
                    .font(.caption.weight(.semibold))

                UnifiedBadge(
                    text: "\(model.trackedPorts.filter { $0.occupied }.count)/\(model.trackedPorts.count)",
                    tint: model.trackedPorts.contains(where: \.occupied) ? .orange : .secondary
                )

                Spacer(minLength: 0)

                // Inline port input + actions
                HStack(spacing: LayoutRules.spacing4) {
                    TextField(L10n.tr("tools.services.port.placeholder"), text: $model.customPortText)
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.center)
                        .frame(width: 68)
                        .frostedRoundedInput(cornerRadius: LayoutRules.radiusTiny)
                        .onSubmit {
                            Task { await model.addTrackedPort() }
                        }

                    Button(L10n.tr("tools.services.action.track")) {
                        Task { await model.addTrackedPort() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)

                    Button {
                        Task { await model.refreshTrackedPorts(showNotice: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .help(L10n.tr("tools.services.action.refresh_port_status"))
                }
            }

            // Port list
            if !model.trackedPorts.isEmpty {
                VStack(spacing: LayoutRules.spacing4) {
                    ForEach(model.trackedPorts) { status in
                        portStatusRow(status)
                    }
                }
            }
        }
        .padding(LayoutRules.spacing10)
        .cardSurface(cornerRadius: LayoutRules.radiusCard, tint: Color.orange.opacity(OpacityScale.ghost))
    }

    private func portStatusRow(_ status: ManagedPortStatus) -> some View {
        let rowTint = status.occupied ? Color.orange : Color.mint

        return HStack(alignment: .center, spacing: LayoutRules.spacing8) {
            Circle()
                .fill(rowTint)
                .frame(width: 7, height: 7)

            Text("\(status.port)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))

            if isDefaultTrackedPort(status.port) {
                UnifiedBadge(text: L10n.tr("tools.services.port.default"), tint: .secondary)
            }

            Text(status.command?.trimmedNonEmpty ?? L10n.tr("tools.services.port.idle"))
                .font(.caption2)
                .foregroundStyle(status.occupied ? .primary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            HStack(spacing: LayoutRules.spacing4) {
                Button(L10n.tr("tools.services.action.release")) {
                    Task { await model.releaseTrackedPort(status.port) }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)
                .disabled(!status.occupied)

                Button(L10n.tr("tools.services.action.force")) {
                    forceKillPort = status.port
                }
                .aimenuActionButtonStyle(density: .compact)
                .disabled(!status.occupied)

                Button(L10n.tr("tools.services.action.untrack")) {
                    Task { await model.untrackPort(status.port) }
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help(L10n.tr("tools.services.action.untrack"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: LayoutRules.radiusSmall, style: .continuous)
                .fill(rowTint.opacity(OpacityScale.ghost))
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutRules.radiusSmall, style: .continuous)
                        .strokeBorder(rowTint.opacity(OpacityScale.subtle), lineWidth: 1)
                )
        )
    }

    private func isDefaultTrackedPort(_ port: Int) -> Bool {
        ToolsPageModel.defaultTrackedPorts.contains(port)
    }
}

// MARK: - Copy Button with Feedback

private struct CopyButton: View {
    let text: String
    @State private var showCheckmark = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeInOut(duration: 0.2)) { showCheckmark = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) { showCheckmark = false }
            }
        } label: {
            Image(systemName: showCheckmark ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(showCheckmark ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.tr("common.action.copy"))
    }
}
