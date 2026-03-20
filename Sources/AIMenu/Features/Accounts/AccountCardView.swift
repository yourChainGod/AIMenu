import SwiftUI

struct AccountCardView: View {
    let account: AccountSummary
    let isCollapsed: Bool
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 8 : 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        stamp(text: planLabel, tint: planTagTint, fg: planTagForeground)
                        if !isCollapsed, let teamNameTag {
                            stamp(text: teamNameTag, tint: workspaceTagTint, fg: workspaceTagForeground)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isCollapsed {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .aimenuActionButtonStyle(
                        prominent: true,
                        tint: .red,
                        density: .compact
                    )
                    .tint(.red)
                }
            }

            Text(displayAccountName)
                .font(.headline)
                .foregroundStyle(account.isCurrent ? toneColor : .primary)
                .lineLimit(isCollapsed ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)

            if isCollapsed {
                compactUsageSection
            } else {
                windowSection(title: L10n.tr("accounts.window.five_hour"), window: account.usage?.fiveHour, tint: .orange)
                windowSection(title: L10n.tr("accounts.window.one_week"), window: account.usage?.oneWeek, tint: .teal)

                HStack(spacing: 4) {
                    if let usageError = account.usageError, !usageError.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(friendlyErrorMessage(usageError))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .help(usageError)
                    } else {
                        Text(L10n.tr("accounts.card.credits_format", creditsText))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, bottomTrailingOverlayInset)

            }
        }
        .padding(isCollapsed ? 8 : 10)
        .cardSurface(
            cornerRadius: 12,
            tint: currentCardSurfaceTint
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(account.isCurrent ? toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if !isCollapsed {
                stamp(
                    text: "代理池成员",
                    tint: toneColor.opacity(OpacityScale.medium),
                    fg: toneColor
                )
                .padding(8)
            }
        }
    }

    // MARK: - Compact Usage

    private var compactUsageSection: some View {
        HStack(spacing: 14) {
            CompactUsageRing(
                usedPercent: compactUsedPercent(account.usage?.fiveHour),
                tint: .orange
            )
            CompactUsageRing(
                usedPercent: compactUsedPercent(account.usage?.oneWeek),
                tint: .teal
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Window Section

    @ViewBuilder
    private func windowSection(title: String, window: UsageWindow?, tint: Color) -> some View {
        let usedRaw = clamped(window?.usedPercent)
        let used = roundedPercent(usedRaw)
        let remain = max(0, 100 - used)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(L10n.tr("accounts.window.used_format", percent(used)))
                    .font(.caption.weight(.semibold))
                Text(L10n.tr("accounts.window.remaining_format", percent(remain)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            usageBar(usedPercent: used, tint: tint)

            Text(L10n.tr("accounts.window.reset_at_format", formatResetAt(window?.resetAt)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed Properties

    private var planLabel: String {
        let normalized = (account.planType ?? account.usage?.planType ?? "team").lowercased()
        switch normalized {
        case "free": return "FREE"
        case "plus": return "PLUS"
        case "pro": return "PRO"
        case "enterprise": return "ENTERPRISE"
        case "business": return "BUSINESS"
        default: return "TEAM"
        }
    }

    private var teamNameTag: String? {
        guard planLabel == "TEAM" else { return nil }
        return account.displayTeamName
    }

    private var toneColor: Color {
        switch planLabel {
        case "PRO": return .orange
        case "PLUS": return .pink
        case "FREE": return .gray
        case "ENTERPRISE", "BUSINESS": return .indigo
        default: return .teal
        }
    }

    private var planTagTint: Color { toneColor.opacity(OpacityScale.medium) }
    private var planTagForeground: Color { toneColor }
    private var workspaceTagTint: Color { toneColor.opacity(OpacityScale.medium) }
    private var workspaceTagForeground: Color { toneColor }

    private var currentCardSurfaceTint: Color? {
        guard account.isCurrent else { return nil }
        return .teal.opacity(OpacityScale.medium)
    }

    private var creditsText: String {
        guard let credits = account.usage?.credits else { return "--" }
        if credits.unlimited { return L10n.tr("accounts.card.unlimited") }
        return credits.balance ?? "--"
    }

    private var bottomTrailingOverlayInset: CGFloat {
        isCollapsed ? 0 : 64
    }

    private var displayAccountName: String {
        let raw = (account.email ?? account.accountID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCollapsed,
              let atIndex = raw.firstIndex(of: "@"),
              atIndex > raw.startIndex else {
            return raw
        }
        return String(raw[..<atIndex])
    }

    // MARK: - Helpers

    private func stamp(text: String, tint: Color, fg: Color, maxWidth: CGFloat? = nil) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(fg)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(tint, in: Capsule())
    }

    private func clamped(_ value: Double?) -> Double {
        guard let value else { return 100 }
        return max(0, min(100, value))
    }

    private func compactUsedPercent(_ window: UsageWindow?) -> Double? {
        guard let used = window?.usedPercent else { return nil }
        return max(0, min(100, used))
    }

    private func roundedPercent(_ value: Double) -> Double {
        Double(Int(value.rounded()))
    }

    private func usageBar(usedPercent: Double, tint: Color) -> some View {
        LiquidProgressBar(
            progress: usedPercent / 100,
            tint: tint
        )
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func friendlyErrorMessage(_ raw: String) -> String {
        if raw.contains("401") { return "认证过期，请重新登录" }
        if raw.contains("403") { return "无权访问" }
        if raw.lowercased().contains("timeout") { return "请求超时" }
        if raw.lowercased().contains("network") || raw.lowercased().contains("connection") { return "网络连接失败" }
        return "用量查询失败"
    }

    private func formatResetAt(_ epoch: Int64?) -> String {
        guard let epoch else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}

// MARK: - CompactUsageRing

struct CompactUsageRing: View {
    let usedPercent: Double?
    let tint: Color

    private var progress: Double {
        guard let usedPercent else { return 0 }
        return max(0, min(1, usedPercent / 100))
    }

    private var percentText: String {
        guard let usedPercent else { return "--" }
        return "\(Int(usedPercent.rounded()))%"
    }

    var body: some View {
        ZStack {
            LiquidProgressRing(
                progress: progress,
                tint: tint,
                lineWidth: 7
            )
            VStack(spacing: 1) {
                Text(percentText)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                Text(L10n.tr("accounts.compact.used"))
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
    }
}
