import SwiftUI
import AppKit

private enum HistoryFilterTab: String, CaseIterable, Identifiable {
    case all
    case transcription
    case translation
    case rewrite
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .transcription:
            return String(localized: "Transcription")
        case .translation:
            return String(localized: "Translation")
        case .rewrite:
            return String(localized: "Rewrite")
        case .meeting:
            return String(localized: "Meeting")
        }
    }

    func matches(_ entry: TranscriptionHistoryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .transcription:
            return entry.kind == .normal
        case .translation:
            return entry.kind == .translation
        case .rewrite:
            return entry.kind == .rewrite
        case .meeting:
            return entry.kind == .meeting
        }
    }
}

struct HistorySettingsView: View {
    private static let pageSize = 40

    @AppStorage(AppPreferenceKey.historyEnabled) private var historyEnabled = false
    @AppStorage(AppPreferenceKey.historyRetentionPeriod) private var historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue

    @ObservedObject var historyStore: TranscriptionHistoryStore
    @ObservedObject var dictionaryStore: DictionaryStore
    @ObservedObject var dictionarySuggestionStore: DictionarySuggestionStore
    let navigationRequest: SettingsNavigationRequest?
    @State private var copiedEntryID: UUID?
    @State private var showRetentionInfo = false
    @State private var selectedFilter: HistoryFilterTab = .all
    @State private var visibleEntryLimit = pageSize

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) ?? .thirtyDays
    }

    private var allEntries: [TranscriptionHistoryEntry] {
        historyStore.allHistoryEntries
    }

    private var filteredEntries: [TranscriptionHistoryEntry] {
        allEntries.filter { selectedFilter.matches($0) }
    }

    private var visibleEntries: [TranscriptionHistoryEntry] {
        Array(filteredEntries.prefix(visibleEntryLimit))
    }

    private var hasMoreFilteredEntries: Bool {
        visibleEntryLimit < filteredEntries.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(String(localized: "Enable Transcription History"), isOn: $historyEnabled)
                                Spacer(minLength: 12)
                                HStack(spacing: 4) {
                                    Text(String(localized: "Retention"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        showRetentionInfo.toggle()
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showRetentionInfo, arrowEdge: .top) {
                                        Text(AppLocalization.localizedString("History older than the selected retention time is automatically deleted."))
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .frame(width: 280, alignment: .leading)
                                    }
                                }
                                SettingsMenuPicker(
                                    selection: $historyRetentionPeriodRaw,
                                    options: HistoryRetentionPeriod.allCases.map { option in
                                        SettingsMenuOption(value: option.rawValue, title: option.title)
                                    },
                                    selectedTitle: historyRetentionPeriod.title,
                                    width: 160
                                )
                                .disabled(!historyEnabled)
                            }

                            Text(String(localized: "When enabled, each completed transcription result will be saved in local history."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .settingsNavigationAnchor(.historySettings)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                HistoryFilterTabPicker(selectedTab: $selectedFilter)
                                Spacer(minLength: 12)
                                Button(String(localized: "Clean All"), role: .destructive) {
                                    copiedEntryID = nil
                                    resetVisibleEntryLimit()
                                    historyStore.clearAll()
                                }
                                .buttonStyle(SettingsPillButtonStyle())
                                .disabled(allEntries.isEmpty)
                            }

                            if allEntries.isEmpty && !historyEnabled {
                                Text(String(localized: "History is currently disabled."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if allEntries.isEmpty {
                                Text(String(localized: "No history yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if filteredEntries.isEmpty {
                                Text(String(localized: "No entries in this category yet."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(visibleEntries) { entry in
                                            HistoryRow(
                                                entry: entry,
                                                meetingAudioURL: historyStore.meetingAudioURL(for: entry),
                                                isCopied: copiedEntryID == entry.id,
                                                onCopy: {
                                                    copyToPasteboard(entry.text)
                                                    copiedEntryID = entry.id
                                                    Task {
                                                        try? await Task.sleep(for: .seconds(1.2))
                                                        if copiedEntryID == entry.id {
                                                            copiedEntryID = nil
                                                        }
                                                    }
                                                },
                                                onDelete: {
                                                    copiedEntryID = nil
                                                    historyStore.delete(id: entry.id)
                                                }
                                            )
                                            .onAppear {
                                                if entry.id == visibleEntries.last?.id {
                                                    loadNextPageIfNeeded()
                                                }
                                            }
                                        }

                                        if hasMoreFilteredEntries {
                                            Button(String(localized: "Load More")) {
                                                loadNextPageIfNeeded()
                                            }
                                            .buttonStyle(SettingsPillButtonStyle())
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .top)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
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
        .onAppear {
            if HistoryRetentionPeriod(rawValue: historyRetentionPeriodRaw) == nil {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue
            }
            resetVisibleEntryLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: historyEnabled) { _, _ in
            resetVisibleEntryLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: historyRetentionPeriodRaw) { _, newValue in
            if HistoryRetentionPeriod(rawValue: newValue) == nil {
                historyRetentionPeriodRaw = HistoryRetentionPeriod.thirtyDays.rawValue
            }
            resetVisibleEntryLimit()
            historyStore.reloadAsync()
        }
        .onChange(of: selectedFilter) { _, _ in
            resetVisibleEntryLimit()
        }
        .onReceive(historyStore.$entries) { _ in
            visibleEntryLimit = min(max(visibleEntryLimit, Self.pageSize), max(filteredEntries.count, Self.pageSize))
        }
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

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func resetVisibleEntryLimit() {
        visibleEntryLimit = Self.pageSize
    }

    private func loadNextPageIfNeeded() {
        guard hasMoreFilteredEntries else { return }
        visibleEntryLimit = min(visibleEntryLimit + Self.pageSize, filteredEntries.count)
    }
}

private struct HistoryFilterTabPicker: View {
    @Binding var selectedTab: HistoryFilterTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilterTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selectedTab == tab))
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

private struct HistoryRow: View {
    @Environment(\.locale) private var locale

    let entry: TranscriptionHistoryEntry
    let meetingAudioURL: URL?
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var showModelInfo = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        historyBadge
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if hasDictionaryActivity {
                            HStack(spacing: 6) {
                                if !entry.dictionaryHitTerms.isEmpty {
                                    activityChip(
                                        label: AppLocalization.format("Dictionary %d", entry.dictionaryHitTerms.count),
                                        color: .secondary
                                    )
                                }
                                if !entry.dictionaryCorrectedTerms.isEmpty {
                                    activityChip(
                                        label: AppLocalization.format("Corrected %d", entry.dictionaryCorrectedTerms.count),
                                        color: .blue
                                    )
                                }
                            }
                        }
                    }

                    if !entry.dictionaryHitTerms.isEmpty {
                        Text("\(String(localized: "Matched dictionary terms")): \(matchedTermsPreview)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        showModelInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelInfo, arrowEdge: .trailing) {
                        HistoryInfoPopover(entry: entry, locale: locale)
                    }

                    Button(String(localized: "Detail")) {
                        openDetailWindow()
                    }
                    .buttonStyle(SettingsPillButtonStyle())

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }

                if isCopied {
                    Text(String(localized: "Copied"))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var hasDictionaryActivity: Bool {
        !entry.dictionaryHitTerms.isEmpty ||
        !entry.dictionaryCorrectedTerms.isEmpty
    }

    private var metadataText: String {
        let dateText = entry.createdAt.formatted(
            .dateTime
                .locale(locale)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
        guard let audioDuration = formattedDuration(entry.audioDurationSeconds) else {
            return dateText
        }
        let format = NSLocalizedString("%@ · Audio: %@", comment: "")
        return String(format: format, locale: locale, dateText, audioDuration)
    }

    private var historyBadge: some View {
        Group {
            if entry.kind == .translation {
                Text(String(localized: "Translation"))
            } else if entry.kind == .rewrite {
                Text(String(localized: "Rewrite"))
            } else if entry.kind == .meeting {
                Text(String(localized: "Meeting"))
            } else {
                Text(String(localized: "Transcription"))
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(historyBadgeColor.opacity(0.16))
        )
        .foregroundStyle(historyBadgeColor)
    }

    private var historyBadgeColor: Color {
        switch entry.kind {
        case .normal:
            return .secondary
        case .translation:
            return .blue
        case .rewrite:
            return .orange
        case .meeting:
            return .green
        }
    }

    private func activityChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }

    private var matchedTermsPreview: String {
        let previewTerms = Array(entry.dictionaryHitTerms.prefix(3))
        let base = previewTerms.joined(separator: ", ")
        let remainingCount = entry.dictionaryHitTerms.count - previewTerms.count
        guard remainingCount > 0 else { return base }
        return "\(base) +\(remainingCount)"
    }

    private func formattedDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        if seconds < 1 {
            let format = NSLocalizedString("%d ms", comment: "")
            return String(format: format, locale: locale, Int(seconds * 1000))
        }
        if seconds < 60 {
            let format = NSLocalizedString("%.1f s", comment: "")
            return String(format: format, locale: locale, seconds)
        }
        let minutes = Int(seconds) / 60
        let remain = Int(seconds) % 60
        let format = NSLocalizedString("%dm %ds", comment: "")
        return String(format: format, locale: locale, minutes, remain)
    }

    private func openDetailWindow() {
        if entry.kind == .meeting {
            guard let appDelegate = AppDelegate.shared else {
                VoxtLog.warning("History detail open skipped: AppDelegate.shared was unavailable.")
                return
            }
            MeetingDetailWindowManager.shared.presentHistoryMeeting(
                entry: entry,
                audioURL: meetingAudioURL,
                initialSummarySettings: appDelegate.currentMeetingSummarySettingsSnapshot(),
                summaryModelOptionsProvider: { @MainActor in
                    appDelegate.meetingSummaryModelOptions()
                },
                summarySettingsProvider: { @MainActor in
                    appDelegate.currentMeetingSummarySettingsSnapshot()
                },
                translationHandler: { @MainActor text, targetLanguage in
                    return try await appDelegate.translateMeetingRealtimeText(text, targetLanguage: targetLanguage)
                },
                summaryStatusProvider: { @MainActor settings in
                    return appDelegate.meetingSummaryProviderStatus(settings: settings)
                },
                summaryGenerator: { @MainActor transcript, settings in
                    return try await appDelegate.generateMeetingSummary(transcript: transcript, settings: settings)
                },
                summaryPersistence: { @MainActor entryID, summary in
                    return appDelegate.persistMeetingSummary(summary, for: entryID)
                },
                summaryChatAnswerer: { @MainActor transcript, summary, history, question, settings in
                    return try await appDelegate.answerMeetingSummaryFollowUp(
                        transcript: transcript,
                        summary: summary,
                        history: history,
                        question: question,
                        settings: settings
                    )
                },
                summaryChatPersistence: { @MainActor entryID, messages in
                    return appDelegate.persistMeetingSummaryChatMessages(messages, for: entryID)
                }
            )
            return
        }

        guard let appDelegate = AppDelegate.shared else {
            VoxtLog.warning("Transcription detail open skipped: AppDelegate.shared was unavailable.")
            return
        }
        appDelegate.showTranscriptionDetailWindow(for: entry)
    }
}

private struct HistoryInfoPopover: View {
    let entry: TranscriptionHistoryEntry
    let locale: Locale

    var body: some View {
        TranscriptionDetailContentView(
            entry: entry,
            locale: locale,
            style: .popover
        )
        .frame(maxHeight: 460)
    }
}
