import SwiftUI

struct PromptEditorView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 100)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}

struct ModelTableAction {
    let title: LocalizedStringKey
    var role: ButtonRole? = nil
    var isEnabled: Bool = true
    let handler: () -> Void
}

struct ModelTableRow: Identifiable {
    let id: String
    let title: String
    let isActive: Bool
    let status: String
    var isTitleUnderlined: Bool = false
    var onTapTitle: (() -> Void)? = nil
    let actions: [ModelTableAction]
}

struct ModelTableView: View {
    let title: LocalizedStringKey
    let rows: [ModelTableRow]
    var maxHeight: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    tableRows
                }
            }
            .frame(maxHeight: maxHeight)
        }
        .tableContainerStyle
    }

    @ViewBuilder
    private var tableRows: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let onTapTitle = row.onTapTitle {
                            Button(action: onTapTitle) {
                                Text(row.title)
                                    .font(.subheadline.weight(row.isActive ? .semibold : .regular))
                                    .underline(row.isTitleUnderlined)
                                    .foregroundStyle(row.isTitleUnderlined ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(row.title)
                                .font(.subheadline.weight(row.isActive ? .semibold : .regular))
                                .underline(row.isTitleUnderlined)
                        }
                        Text(row.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        ForEach(Array(row.actions.enumerated()), id: \.offset) { _, action in
                            Button(action.title, role: action.role) {
                                action.handler()
                            }
                            .controlSize(.small)
                            .disabled(!action.isEnabled)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private extension View {
    var tableContainerStyle: some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
