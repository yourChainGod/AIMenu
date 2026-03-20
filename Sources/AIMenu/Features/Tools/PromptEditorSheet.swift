import SwiftUI

struct PromptEditorSheet: View {
    let appType: PromptAppType
    let prompt: Prompt?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var content: String

    init(
        appType: PromptAppType,
        prompt: Prompt?,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.appType = appType
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: prompt?.name ?? "")
        _content = State(initialValue: prompt?.content ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt == nil ? L10n.tr("tools.prompt_editor.title.add") : L10n.tr("tools.prompt_editor.title.edit"))
                        .font(.headline)
                    Text(L10n.tr("tools.prompt_editor.subtitle.write_to_format", appType.fileName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .keyboardShortcut(.escape)
                Button(prompt == nil ? L10n.tr("common.add") : L10n.tr("common.save")) {
                    onSave(name, content)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("common.name"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(L10n.tr("tools.prompt_editor.name_placeholder"), text: $name)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("common.content"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $content)
                        .font(.body)
                        .padding(8)
                        .frame(minHeight: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(20)
        }
    }
}
