import SwiftUI
import AppKit

struct ToolsConfigsSection: View {
    @ObservedObject var model: ToolsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolsHelpers.overviewActionStrip(
                title: "刷新配置",
                tint: .green,
                help: "刷新本地配置状态"
            ) {
                Task { await model.refreshLocalConfigBundles() }
            }

            localConfigContent
        }
    }

    @ViewBuilder
    private var localConfigContent: some View {
        if model.localConfigBundles.isEmpty {
            ToolsHelpers.compactEmptyState(
                icon: "folder.badge.gearshape",
                title: "暂无本地配置概览",
                message: "扫描到配置文件后会在这里汇总显示。",
                tint: .green
            )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(model.localConfigBundles) { bundle in
                    localConfigBundleCard(bundle)
                }
            }
        }
    }

    private func localConfigBundleCard(_ bundle: LocalConfigBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ToolsHelpers.localConfigAccent(for: bundle.app).opacity(OpacityScale.muted))
                        .frame(width: 38, height: 38)
                    Image(systemName: bundle.app.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ToolsHelpers.localConfigAccent(for: bundle.app))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(bundle.app.displayName)
                            .font(.headline)
                        UnifiedBadge(
                            text: "\(bundle.existingFileCount)/\(bundle.files.count)",
                            tint: bundle.existingFileCount == bundle.files.count ? Color.mint : Color.orange
                        )
                    }
                    Text(ToolsHelpers.tildePath(bundle.rootPath))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let latestText = ToolsHelpers.localConfigLatestText(bundle.latestModifiedAt) {
                        Text(latestText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    ToolsHelpers.openDirectory(bundle.rootPath)
                } label: {
                    Image(systemName: "folder")
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .disabled(bundle.existingFileCount == 0)
                .help("打开 \(bundle.app.displayName) 配置目录")
            }

            VStack(spacing: 6) {
                ForEach(bundle.files) { file in
                    localConfigFileRow(file)
                }
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: ToolsHelpers.localConfigAccent(for: bundle.app).opacity(OpacityScale.subtle))
    }

    private func localConfigFileRow(_ file: LocalConfigFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(file.exists ? Color.mint : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.label)
                        .font(.caption.weight(.semibold))
                    UnifiedBadge(text: file.kind.displayName, tint: ToolsHelpers.localConfigKindTint(file.kind))
                    UnifiedBadge(
                        text: file.exists ? "可见" : "缺失",
                        tint: file.exists ? Color.mint : Color.secondary
                    )
                }

                Text(ToolsHelpers.tildePath(file.path))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let metaText = ToolsHelpers.localConfigMetaText(file) {
                    Text(metaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if file.exists {
                Button {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help("在 Finder 中定位 \(file.label)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(OpacityScale.ghost), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
