import SwiftUI
import AppKit

struct MCPServerEditorSheet: View {
    let server: MCPServer?
    let onSave: (MCPServer) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var transport: MCPTransportType
    @State private var command: String
    @State private var argsText: String
    @State private var urlText: String
    @State private var envText: String
    @State private var headersText: String
    @State private var cwd: String
    @State private var description: String
    @State private var homepage: String
    @State private var tags: String
    @State private var enabled = true
    @State private var enableClaude = true
    @State private var enableCodex = true
    @State private var enableGemini = true

    init(
        server: MCPServer?,
        onSave: @escaping (MCPServer) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.server = server
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: server?.name ?? "")
        _transport = State(initialValue: server?.server.type ?? .stdio)
        _command = State(initialValue: server?.server.command ?? "")
        _argsText = State(initialValue: (server?.server.args ?? []).joined(separator: "\n"))
        _urlText = State(initialValue: server?.server.url ?? "")
        _envText = State(initialValue: Self.dictToMultiline(server?.server.env ?? [:]))
        _headersText = State(initialValue: Self.dictToMultiline(server?.server.headers ?? [:]))
        _cwd = State(initialValue: server?.server.cwd ?? "")
        _description = State(initialValue: server?.description ?? "")
        _homepage = State(initialValue: server?.homepage ?? "")
        _tags = State(initialValue: (server?.tags ?? []).joined(separator: ", "))
        _enabled = State(initialValue: server?.isEnabled ?? true)
        _enableClaude = State(initialValue: server?.apps.claude ?? true)
        _enableCodex = State(initialValue: server?.apps.codex ?? true)
        _enableGemini = State(initialValue: server?.apps.gemini ?? true)
    }

    private var canSave: Bool {
        guard name.trimmedNonEmpty != nil else { return false }
        switch transport {
        case .stdio: return command.trimmedNonEmpty != nil
        case .http, .sse: return urlText.trimmedNonEmpty != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server == nil ? L10n.tr("tools.mcp_editor.title.add") : L10n.tr("tools.mcp_editor.title.edit"))
                        .font(.headline)
                    Text(L10n.tr("tools.mcp_editor.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.escape)
                Button(server == nil ? L10n.tr("common.add") : L10n.tr("common.save")) {
                    onSave(buildServer())
                }
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldGroup(title: L10n.tr("tools.mcp_editor.section.basic")) {
                        HStack(alignment: .top, spacing: 12) {
                            labeledField(L10n.tr("common.name")) {
                                TextField(L10n.tr("tools.mcp_editor.name_placeholder"), text: $name)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField(L10n.tr("tools.mcp_editor.transport")) {
                                Picker("", selection: $transport) {
                                    ForEach(MCPTransportType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        Toggle(L10n.tr("tools.mcp_editor.toggle.enable_server"), isOn: $enabled)
                            .toggleStyle(.checkbox)
                        HStack(spacing: 8) {
                            toggleChip("Claude", isOn: $enableClaude)
                            toggleChip("Codex", isOn: $enableCodex)
                            toggleChip("Gemini", isOn: $enableGemini)
                        }
                    }

                    fieldGroup(
                        title: transport == .stdio
                            ? L10n.tr("tools.mcp_editor.section.process")
                            : L10n.tr("tools.mcp_editor.section.remote")
                    ) {
                        if transport == .stdio {
                            labeledField(L10n.tr("common.command")) {
                                TextField(L10n.tr("tools.mcp_editor.command_placeholder"), text: $command)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField(L10n.tr("tools.mcp_editor.arguments")) {
                                TextEditor(text: $argsText)
                                    .frame(minHeight: 92)
                                    .padding(8)
                                    .background(editorBackground)
                            }
                            labeledField(L10n.tr("tools.mcp_editor.cwd")) {
                                TextField(L10n.tr("common.optional"), text: $cwd)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        } else {
                            labeledField(L10n.tr("common.url")) {
                                TextField("https://example.com/mcp", text: $urlText)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        }
                    }

                    fieldGroup(title: L10n.tr("tools.mcp_editor.section.metadata")) {
                        labeledField(L10n.tr("tools.mcp_editor.environment")) {
                            TextEditor(text: $envText)
                                .frame(minHeight: 92)
                                .padding(8)
                                .background(editorBackground)
                        }
                        labeledField(L10n.tr("tools.mcp_editor.headers")) {
                            TextEditor(text: $headersText)
                                .frame(minHeight: 92)
                                .padding(8)
                                .background(editorBackground)
                        }
                        labeledField(L10n.tr("common.description")) {
                            TextField(L10n.tr("tools.mcp_editor.description_placeholder"), text: $description)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            labeledField(L10n.tr("common.homepage")) {
                                TextField("https://", text: $homepage)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField(L10n.tr("common.tags")) {
                                TextField(L10n.tr("tools.mcp_editor.tags_placeholder"), text: $tags)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(OpacityScale.subtle))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(OpacityScale.muted), lineWidth: 1)
            )
    }

    private func fieldGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .background(Color.primary.opacity(OpacityScale.faint), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn.wrappedValue ? Color.mint : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isOn.wrappedValue ? Color.mint.opacity(OpacityScale.muted) : Color.primary.opacity(OpacityScale.subtle))
            )
        }
        .buttonStyle(.plain)
    }

    private func buildServer() -> MCPServer {
        let now = Int64(Date().timeIntervalSince1970)
        return MCPServer(
            id: server?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            server: MCPServerSpec(
                type: transport,
                command: transport == .stdio ? command.trimmedNonEmpty : nil,
                args: transport == .stdio ? lines(from: argsText) : nil,
                env: dictionary(from: envText),
                cwd: transport == .stdio ? cwd.trimmedNonEmpty : nil,
                url: transport == .stdio ? nil : urlText.trimmedNonEmpty,
                headers: dictionary(from: headersText)
            ),
            apps: MCPAppToggles(
                claude: enableClaude,
                codex: enableCodex,
                gemini: enableGemini
            ),
            description: description.trimmedNonEmpty,
            tags: csvItems(from: tags),
            homepage: homepage.trimmedNonEmpty,
            createdAt: server?.createdAt ?? now,
            updatedAt: now,
            isEnabled: enabled
        )
    }

    private func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .compactMap { $0.trimmedNonEmpty }
    }

    private func csvItems(from text: String) -> [String]? {
        let values = text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func dictionary(from text: String) -> [String: String]? {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    private static func dictToMultiline(_ value: [String: String]) -> String {
        value.keys.sorted().map { "\($0)=\(value[$0] ?? "")" }.joined(separator: "\n")
    }
}
