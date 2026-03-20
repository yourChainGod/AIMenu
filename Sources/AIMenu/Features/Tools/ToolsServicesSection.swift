import SwiftUI
import AppKit

struct ToolsServicesSection: View {
    @ObservedObject var model: ToolsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing12) {
            cursor2APIServiceCard
            portToolsCard
        }
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

                Text("Cursor2API")
                    .font(.subheadline.weight(.semibold))

                UnifiedBadge(
                    text: model.cursor2APIStatus.running ? "运行中" : (model.cursor2APIStatus.installed ? "已安装" : "未安装"),
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
                .help("刷新服务状态")
            }

            // Compact info strip: port + API key + model in a single row
            HStack(spacing: LayoutRules.spacing6) {
                compactMetric(label: "端口", value: "\(model.cursor2APIStatus.port)", tint: .blue)
                compactMetric(label: "Key", value: ToolsHelpers.maskedSecret(model.cursor2APIStatus.apiKey), tint: .mint)
                compactMetric(
                    label: "模型",
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
                Button(model.cursor2APIStatus.installed ? "重新安装" : "安装") {
                    Task { await model.installCursor2API() }
                }
                .aimenuActionButtonStyle(density: .compact)

                if model.cursor2APIStatus.running {
                    Button("停止") {
                        Task { await model.stopCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .red, density: .compact)
                } else {
                    Button("启动") {
                        Task { await model.startCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                    .disabled(!model.cursor2APIStatus.installed)
                }

                Button("应用到 Claude") {
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
                    .help("查看日志")
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
                    .help("查看配置")
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
                Label("端口管理", systemImage: "wave.3.right")
                    .font(.caption.weight(.semibold))

                UnifiedBadge(
                    text: "\(model.trackedPorts.filter { $0.occupied }.count)/\(model.trackedPorts.count)",
                    tint: model.trackedPorts.contains(where: \.occupied) ? .orange : .secondary
                )

                Spacer(minLength: 0)

                // Inline port input + actions
                HStack(spacing: LayoutRules.spacing4) {
                    TextField("端口号", text: $model.customPortText)
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.center)
                        .frame(width: 68)
                        .frostedRoundedInput(cornerRadius: LayoutRules.radiusTiny)
                        .onSubmit {
                            Task { await model.addTrackedPort() }
                        }

                    Button("关注") {
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
                    .help("刷新端口状态")
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
                UnifiedBadge(text: "默认", tint: .secondary)
            }

            Text(status.command?.trimmedNonEmpty ?? "空闲")
                .font(.caption2)
                .foregroundStyle(status.occupied ? .primary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            HStack(spacing: LayoutRules.spacing4) {
                Button("解除") {
                    Task { await model.releaseTrackedPort(status.port) }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)
                .disabled(!status.occupied)

                Button("强制") {
                    Task { await model.releaseTrackedPort(status.port, force: true) }
                }
                .aimenuActionButtonStyle(density: .compact)
                .disabled(!status.occupied)

                if !isDefaultTrackedPort(status.port) {
                    Button {
                        Task { await model.removeTrackedPort(status.port) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("移除此端口")
                }
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
        [8002, 8787].contains(port)
    }
}
