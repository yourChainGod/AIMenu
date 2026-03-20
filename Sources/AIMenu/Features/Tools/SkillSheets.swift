import SwiftUI
import AppKit

struct DiscoverableSkillPreviewSheet: View {
    let document: DiscoverableSkillPreviewDocument
    let previewLoading: Bool
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(document.skill.name)
                            .font(.headline)
                        Text(repoLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(OpacityScale.subtle), in: Capsule())
                    }

                    if let description = document.skill.description?.trimmedNonEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(document.sourcePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let sourceURL = sourceURL {
                        Button(L10n.tr("common.repository")) {
                            NSWorkspace.shared.open(sourceURL)
                        }
                        .aimenuActionButtonStyle(density: .compact)
                    }

                    if document.skill.isInstalled {
                        Text(L10n.tr("tools.skill.installed"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.mint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.mint.opacity(OpacityScale.muted), in: Capsule())
                    } else {
                        Button(L10n.tr("common.install")) {
                            onInstall()
                        }
                        .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                    }

                    Button(L10n.tr("common.close")) {
                        onDismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: "SKILL.md")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if previewLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                ScrollView {
                    Text(verbatim: document.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(OpacityScale.subtle))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(OpacityScale.muted), lineWidth: 1)
                        )
                )
            }
            .padding(20)
        }
    }

    private var repoLabel: String {
        "\(document.skill.repoOwner)/\(document.skill.repoName)"
    }

    private var sourceURL: URL? {
        guard let urlString = document.skill.readmeUrl else { return nil }
        return URL(string: urlString)
    }
}

struct InstalledSkillEditorSheet: View {
    let document: InstalledSkillDocument
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var content: String

    init(
        document: InstalledSkillDocument,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.document = document
        self.onSave = onSave
        self.onCancel = onCancel
        _content = State(initialValue: document.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(document.skill.name)
                            .font(.headline)
                        Text(repoLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(OpacityScale.subtle), in: Capsule())
                    }
                    Text(document.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.escape)
                Button(L10n.tr("common.save")) {
                    onSave(content)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: "SKILL.md")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(L10n.tr("common.open_in_finder")) {
                        NSWorkspace.shared.selectFile(document.path, inFileViewerRootedAtPath: "")
                    }
                    .aimenuActionButtonStyle(density: .compact)
                }

                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(OpacityScale.subtle))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(OpacityScale.muted), lineWidth: 1)
                            )
                    )
            }
            .padding(20)
        }
    }

    private var repoLabel: String {
        let owner = document.skill.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = document.skill.repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty, !repo.isEmpty {
            return "\(owner)/\(repo)"
        }
        return L10n.tr("tools.skill.local")
    }
}

struct SkillRepoEditorSheet: View {
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var owner = ""
    @State private var name = ""
    @State private var branch = "main"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("tools.skill_repo_editor.title"))
                        .font(.headline)
                    Text(L10n.tr("tools.skill_repo_editor.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.escape)
                Button(L10n.tr("common.save")) {
                    onSave(owner, name, branch)
                }
                .disabled(owner.trimmedNonEmpty == nil || name.trimmedNonEmpty == nil || branch.trimmedNonEmpty == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("common.owner"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(L10n.tr("tools.skill_repo_editor.owner_placeholder"), text: $owner)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("common.repository"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(L10n.tr("tools.skill_repo_editor.repository_placeholder"), text: $name)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("common.branch"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("main", text: $branch)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}
