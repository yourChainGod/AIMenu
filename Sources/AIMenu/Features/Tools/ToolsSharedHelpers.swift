import SwiftUI
import AppKit

// MARK: - Shared enums used by ToolsPageView and section views

enum ToolsOverviewSection: CaseIterable, Identifiable {
    case services
    case configs

    var id: Self { self }

    var title: String {
        switch self {
        case .services: return "本地服务"
        case .configs: return "本地配置"
        }
    }

    var iconName: String {
        switch self {
        case .services: return "switch.2"
        case .configs: return "folder.badge.gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .services: return .teal
        case .configs: return .green
        }
    }
}

enum SkillsFilter: String, CaseIterable, Identifiable {
    case all
    case installed
    case discoverable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .installed: return "已装"
        case .discoverable: return "可装"
        }
    }
}

// MARK: - Shared helper views and functions

@MainActor
struct ToolsHelpers {

    static func workbenchMoreMenu<Content: View>(
        title: String = "更多",
        systemImage: String = "ellipsis",
        help text: String = "更多操作",
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .aimenuActionButtonStyle(density: .compact)
        .help(text)
    }

    static func workbenchActionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        prominent: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .aimenuActionButtonStyle(prominent: prominent, tint: tint, density: .compact)
        .help(help ?? title)
    }

    static func workbenchStrip<Content: View>(
        tint: Color? = nil,
        minHeight: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: minHeight == 0 ? nil : minHeight, alignment: .leading)
        .cardSurface(cornerRadius: 12, tint: tint?.opacity(OpacityScale.subtle))
    }

    static func compactEmptyState(
        icon: String,
        title: String,
        message: String? = nil,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(OpacityScale.muted))
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 104)
        .cardSurface(cornerRadius: 14, tint: tint.opacity(OpacityScale.subtle))
    }

    static func overviewActionStrip(
        title: String,
        systemImage: String = "arrow.clockwise",
        tint: Color,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            workbenchActionButton(
                title,
                systemImage: systemImage,
                tint: tint,
                prominent: true,
                help: help ?? title,
                action: action
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    static func appMountChip(
        app: ProviderAppType,
        label: String? = nil,
        isOn: Bool,
        disabled: Bool = false,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        let tint = localConfigAccent(for: app)
        let title = label ?? compactAppName(for: app)

        return Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? tint : Color.secondary.opacity(OpacityScale.accent))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? tint.opacity(OpacityScale.muted) : Color.primary.opacity(OpacityScale.subtle))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isOn ? tint.opacity(OpacityScale.accent) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }

    static func compactAppName(for app: ProviderAppType) -> String {
        switch app {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini"
        }
    }

    static func localConfigAccent(for app: ProviderAppType) -> Color {
        switch app {
        case .claude:
            return .green
        case .codex:
            return .blue
        case .gemini:
            return .orange
        }
    }

    static func localConfigKindTint(_ kind: LocalConfigKind) -> Color {
        switch kind {
        case .json:
            return .blue
        case .toml:
            return .purple
        case .env:
            return .orange
        case .markdown:
            return .secondary
        }
    }

    static func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func openDirectory(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    static func relativeDateString(_ timestamp: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }

    static func serviceMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((tint == .secondary ? Color.primary : tint).opacity(OpacityScale.subtle))
        )
    }

    static func maskedSecret(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return "\(trimmed.prefix(4))•••\(trimmed.suffix(4))"
    }

    static func localConfigMetaText(_ file: LocalConfigFile) -> String? {
        guard file.exists else { return nil }

        var parts: [String] = []
        if let byteCount = file.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append(relativeDateString(modifiedAt))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func localConfigLatestText(_ timestamp: Int64?) -> String? {
        guard let timestamp else { return nil }
        return "最近更新 \(relativeDateString(timestamp))"
    }

    static func installedSkillPath(for skill: InstalledSkill) -> String {
        NSHomeDirectory() + "/Library/Application Support/\(FileSystemPaths.appSupportDirectoryName)/skills/\(skill.directory)"
    }
}
