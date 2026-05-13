import SwiftUI

struct DictionarySettingsHeaderCard: View {
    let historyScanProgress: DictionaryHistoryScanProgress
    let suggestionActionMessage: String?
    let onOpenIngest: () -> Void
    let onOpenSettings: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void
    let historyScanSummaryText: (Date) -> String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Button(AppLocalization.localizedString("One-Click Ingest")) {
                        onOpenIngest()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Spacer(minLength: 12)

                    Button {
                        onOpenSettings()
                    } label: {
                        Text(AppLocalization.localizedString("Settings"))
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .help(AppLocalization.localizedString("Dictionary Advanced Settings"))

                    DictionaryHeaderActionMenuButton(
                        actions: [
                            DictionaryHeaderMenuAction(title: AppLocalization.localizedString("Import"), handler: onImport),
                            DictionaryHeaderMenuAction(title: AppLocalization.localizedString("Export"), handler: onExport)
                        ]
                    )
                    .frame(width: 28, height: 28)
                    .help(AppLocalization.localizedString("More"))
                }

                DictionarySettingsHeaderStatus(
                    historyScanProgress: historyScanProgress,
                    suggestionActionMessage: suggestionActionMessage,
                    historyScanSummaryText: historyScanSummaryText
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DictionarySettingsHeaderStatus: View {
    let historyScanProgress: DictionaryHistoryScanProgress
    let suggestionActionMessage: String?
    let historyScanSummaryText: (Date) -> String

    var body: some View {
        if let errorMessage = historyScanProgress.errorMessage,
           !errorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(AppLocalization.localizedString("Review the ingest prompt in One-Click Ingest, then try again."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let lastRunAt = historyScanProgress.lastRunAt {
            Text(historyScanSummaryText(lastRunAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let suggestionActionMessage, !suggestionActionMessage.isEmpty {
            Text(suggestionActionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DictionaryEntriesCard: View {
    @Binding var selectedFilter: DictionaryFilter
    let visibleEntries: [DictionaryEntry]
    let searchText: String
    let dictionaryTransferMessage: String?
    let scopeLabel: (DictionaryEntry) -> String
    let scopeIsMissing: (DictionaryEntry) -> Bool
    let onSearch: () -> Void
    let onClearSearch: () -> Void
    let onCreate: () -> Void
    let onClearAll: () -> Void
    let onEdit: (DictionaryEntry) -> Void
    let onDelete: (DictionaryEntry) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DictionaryFilterPicker(selectedFilter: $selectedFilter)

                    Spacer(minLength: 12)

                    Button {
                        onSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(SettingsCompactIconButtonStyle())
                    .help(AppLocalization.localizedString("Search Dictionary"))

                    Button(AppLocalization.localizedString("Create")) {
                        onCreate()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(AppLocalization.localizedString("Clean All"), role: .destructive) {
                        onClearAll()
                    }
                    .buttonStyle(SettingsStatusButtonStyle(tint: .red))
                    .disabled(visibleEntries.isEmpty)
                }

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Text(AppLocalization.format("Filtered by \"%@\"", searchText))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(AppLocalization.localizedString("Clear")) {
                            onClearSearch()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if visibleEntries.isEmpty {
                    Text(emptyStateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VirtualizedVerticalList(
                        items: visibleEntries,
                        rowHeight: 64,
                        rowSpacing: 6
                    ) { entry in
                        DictionaryRow(
                            entry: entry,
                            scopeLabel: scopeLabel(entry),
                            scopeIsMissing: scopeIsMissing(entry),
                            onEdit: { onEdit(entry) },
                            onDelete: { onDelete(entry) }
                        )
                    }
                    .frame(minHeight: 240, idealHeight: 420, maxHeight: 520, alignment: .top)
                }

                if let dictionaryTransferMessage, !dictionaryTransferMessage.isEmpty {
                    Text(dictionaryTransferMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyStateText: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLocalization.localizedString("No dictionary terms yet.")
        }
        return AppLocalization.localizedString("No dictionary terms match this search.")
    }
}
