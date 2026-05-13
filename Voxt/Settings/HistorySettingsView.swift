import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private enum HistoryBulkDeletionTarget: Identifiable {
    case history
    case notes

    var id: String {
        switch self {
        case .history:
            return "history"
        case .notes:
            return "notes"
        }
    }
}

struct HistorySettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(AppPreferenceKey.historyCleanupEnabled) private var historyCleanupEnabled = true
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
    @AppStorage(AppPreferenceKey.historyAudioStorageEnabled) private var historyAudioStorageEnabled = false

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var noteStore: VoxtNoteStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let navigationRequest: SettingsNavigationRequest?
    @State private var copiedEntryID: UUID?
    @State private var copiedNoteID: UUID?
    @State private var selectedFilter: HistoryFilterTab = .transcription
    @State private var isHistoryAudioSettingsPresented = false
    @State private var historyAudioStorageDisplayPath = ""
    @State private var historyAudioStorageSelectionError: String?
    @State private var historyAudioExportResultMessage: String?
    @State private var historyAudioStorageStats = HistoryAudioStorageStats(storedFileCount: 0, totalBytes: 0)
    @State private var pendingBulkDeletionTarget: HistoryBulkDeletionTarget?
    @State private var selectedHistoryInfoEntry: TranscriptionHistoryEntry?
    @State private var historySearchText = ""
    @State private var showHistorySearchDialog = false

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .ninetyDays
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        let entries = HistorySettingsData.filteredEntries(
            for: selectedFilter,
            allEntries: historyStore.allHistoryEntries
        )
        return HistorySettingsData.searchEntries(entries, query: historySearchText)
    }

    private var allNotes: [VoxtNoteItem] {
        HistorySettingsData.searchNotes(noteStore.items, query: historySearchText)
    }

    private var visibleNotes: [VoxtNoteItem] {
        allNotes
    }

    private var visibleEntries: [TranscriptionHistoryEntry] {
        filteredEntries
    }

    private var isNoteTabSelected: Bool {
        selectedFilter == .note
    }

    private var isSearchActive: Bool {
        !historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyState: HistoryContentEmptyState {
        HistorySettingsData.emptyState(
            selectedFilter: selectedFilter,
            allEntries: historyStore.allHistoryEntries,
            filteredEntries: filteredEntries,
            notes: allNotes
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                HistoryFilterTabPicker(selectedTab: $selectedFilter)
                                Spacer(minLength: 12)
                                Button {
                                    showHistorySearchDialog = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .buttonStyle(SettingsCompactIconButtonStyle())
                                .help(localized("Search History"))
                                Button {
                                    pendingBulkDeletionTarget = isNoteTabSelected ? .notes : .history
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive))
                                .help(localized("Delete All"))
                                .disabled(isNoteTabSelected ? allNotes.isEmpty : historyStore.allHistoryEntries.isEmpty)
                                Button {
                                    historyAudioStorageSelectionError = nil
                                    historyAudioExportResultMessage = nil
                                    isHistoryAudioSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                                .buttonStyle(SettingsCompactIconButtonStyle())
                            }

                            if isSearchActive {
                                HStack(spacing: 8) {
                                    Text(AppLocalization.format("Filtered by \"%@\"", historySearchText))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Button(localized("Clear")) {
                                        historySearchText = ""
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if let emptyStateKey = emptyState.localizedKey {
                                Text(localized(emptyStateKey))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if isNoteTabSelected {
                                notesList
                            } else {
                                historyList
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .settingsNavigationAnchor(.historySettings)
                    .settingsNavigationAnchor(.historyEntries)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onAppear {
                scrollToNavigationTargetIfNeeded(using: proxy)
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                scrollToNavigationTargetIfNeeded(using: proxy)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $isHistoryAudioSettingsPresented) {
            HistoryAudioSettingsSheet(
                historyCleanupEnabled: $historyCleanupEnabled,
                historyRetentionPeriodRaw: $historyRetentionPeriodRaw,
                historyAudioStorageEnabled: $historyAudioStorageEnabled,
                historyAudioStorageDisplayPath: $historyAudioStorageDisplayPath,
                historyAudioStorageSelectionError: $historyAudioStorageSelectionError,
                historyAudioExportResultMessage: $historyAudioExportResultMessage,
                isPresented: $isHistoryAudioSettingsPresented,
                historyRetentionPeriod: historyRetentionPeriod,
                historyAudioStorageStatsSummary: historyAudioStorageStatsSummary,
                onOpenHistoryAudioStorageInFinder: openHistoryAudioStorageInFinder,
                onChooseHistoryAudioStorageDirectory: chooseHistoryAudioStorageDirectory,
                onExportAllHistoryAudio: exportAllHistoryAudio
            )
        }
        .sheet(item: $selectedHistoryInfoEntry) { entry in
            HistoryDetailSheetContent(
                entry: entry,
                audioURL: historyStore.audioURL(for: entry),
                locale: locale
            )
            .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 640)
        }
        .sheet(isPresented: $showHistorySearchDialog) {
            SettingsSearchDialog(
                title: localized("Search History"),
                placeholder: localized("Search text, title, app, or dictionary terms"),
                query: $historySearchText,
                isPresented: $showHistorySearchDialog
            )
        }
        .alert(item: $pendingBulkDeletionTarget) { target in
            Alert(
                title: Text(bulkDeletionTitle(for: target)),
                message: Text(bulkDeletionMessage(for: target)),
                primaryButton: .destructive(Text(localized("Delete"))) {
                    confirmBulkDeletion(target)
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == historyRetentionPeriodRaw }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            refreshHistoryAudioStorageDisplayPath()
            refreshHistoryAudioStorageStats()
            historyStore.reloadAsync()
        }
        .onChange(of: historyCleanupEnabled) { _, _ in
            historyStore.reloadAsync()
        }
        .onChange(of: historyRetentionPeriodRaw) { _, newValue in
            if !HistoryRetentionPeriod.allCases.contains(where: { $0.rawValue == newValue }) {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.ninetyDays.rawValue
            }
            historyStore.reloadAsync()
        }
        .onReceive(historyStore.$entries) { _ in
            refreshHistoryAudioStorageStats()
        }
    }

    private var notesList: some View {
        VirtualizedVerticalList(
            items: visibleNotes,
            rowHeight: 94,
            rowSpacing: 8
        ) { item in
            NoteHistoryRow(
                item: item,
                isCopied: copiedNoteID == item.id,
                onCopy: {
                    copyStringToPasteboard(item.text)
                    copiedNoteID = item.id
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if copiedNoteID == item.id {
                            copiedNoteID = nil
                        }
                    }
                },
                onToggleCompletion: {
                    _ = noteStore.updateCompletion(!item.isCompleted, for: item.id)
                },
                onDelete: {
                    copiedNoteID = nil
                    noteStore.delete(id: item.id)
                }
            )
        }
        .frame(minHeight: 260, idealHeight: 480, maxHeight: 580, alignment: .top)
    }

    private var historyList: some View {
        VirtualizedVerticalList(
            items: visibleEntries,
            rowHeight: 104,
            rowSpacing: 8
        ) { entry in
            HistoryRow(
                entry: entry,
                audioURL: historyStore.audioURL(for: entry),
                isCopied: copiedEntryID == entry.id,
                onCopy: {
                    copyStringToPasteboard(
                        HistoryCorrectionPresentation.correctedText(
                            for: entry.text,
                            snapshots: entry.dictionaryCorrectionSnapshots
                        )
                    )
                    copiedEntryID = entry.id
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if copiedEntryID == entry.id {
                            copiedEntryID = nil
                        }
                    }
                },
                onShowInfo: {
                    selectedHistoryInfoEntry = entry
                },
                onDelete: {
                    copiedEntryID = nil
                    historyStore.delete(id: entry.id)
                }
            )
        }
        .frame(minHeight: 260, idealHeight: 480, maxHeight: 580, alignment: .top)
    }

    private func scrollToNavigationTargetIfNeeded(using proxy: ScrollViewProxy) {
        guard let navigationRequest,
              navigationRequest.target.tab == .history,
              let section = navigationRequest.target.section
        else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(section.rawValue, anchor: .top)
            }
        }
    }

    private func confirmBulkDeletion(_ target: HistoryBulkDeletionTarget) {
        copiedEntryID = nil
        copiedNoteID = nil
        switch target {
        case .history:
            historyStore.clearAll()
        case .notes:
            noteStore.clearAll()
        }
    }

    private func bulkDeletionTitle(for target: HistoryBulkDeletionTarget) -> String {
        switch target {
        case .history:
            return localized("Delete All History?")
        case .notes:
            return localized("Delete All Notes?")
        }
    }

    private func bulkDeletionMessage(for target: HistoryBulkDeletionTarget) -> String {
        switch target {
        case .history:
            return localized("This will permanently delete all history entries.")
        case .notes:
            return localized("This will permanently delete all notes.")
        }
    }

    private func openHistoryAudioStorageInFinder() {
        HistoryAudioStorageDirectoryManager.openRootInFinder()
    }

    private func chooseHistoryAudioStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = HistoryAudioStorageDirectoryManager.resolvedRootURL()

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            try HistoryAudioStorageDirectoryManager.saveUserSelectedRootURL(selectedURL)
            historyAudioStorageSelectionError = nil
            refreshHistoryAudioStorageDisplayPath()
        } catch {
            historyAudioStorageSelectionError = AppLocalization.format(
                "Failed to update history audio storage path: %@",
                error.localizedDescription
            )
        }
    }

    private func refreshHistoryAudioStorageDisplayPath() {
        historyAudioStorageDisplayPath = HistoryAudioStorageDirectoryManager.resolvedRootURL().path
    }

    private func refreshHistoryAudioStorageStats() {
        historyAudioStorageStats = historyStore.currentAudioArchiveStorageStats()
    }

    private var historyAudioStorageStatsSummary: String {
        AppLocalization.format(
            "Saved audio: %d files · %@",
            historyAudioStorageStats.storedFileCount,
            formattedByteCount(historyAudioStorageStats.totalBytes)
        )
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func exportAllHistoryAudio() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let summary = try historyStore.exportAllAudioArchives(to: destinationURL)
            historyAudioExportResultMessage = AppLocalization.format(
                "Exported %d audio files. Skipped %d. Failed %d.",
                summary.exportedCount,
                summary.skippedCount,
                summary.failedCount
            )
        } catch {
            historyAudioExportResultMessage = AppLocalization.format(
                "Audio export failed: %@",
                error.localizedDescription
            )
        }
        refreshHistoryAudioStorageStats()
    }
}
