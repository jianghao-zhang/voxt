import SwiftUI

func featureSettingsLocalized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

func featureSettingsLocalizedKey(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(AppLocalization.localizedString(key))
}

extension FeatureSettingsView {
    func promptBinding(
        get: @escaping () -> String,
        set: @escaping (String) -> Void,
        kind: AppPromptKind
    ) -> Binding<String> {
        Binding(
            get: {
                AppPromptDefaults.resolvedStoredText(get(), kind: kind)
            },
            set: { newValue in
                set(AppPromptDefaults.canonicalStoredText(newValue, kind: kind))
            }
        )
    }

    var transcriptionPills: [FeatureSummaryPill] {
        var pills = [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.transcription.asrSelectionID)))
        ]
        pills.append(
            FeatureSummaryPill(
                title: featureSettingsLocalized("LLM"),
                value: featureSettings.transcription.llmEnabled
                    ? shortSummary(llmSelectionSummary(featureSettings.transcription.llmSelectionID))
                    : featureSettingsLocalized("Off")
            )
        )
        pills.append(
            FeatureSummaryPill(
                title: featureSettingsLocalized("App"),
                value: featureSettings.rewrite.appEnhancementEnabled ? featureSettingsLocalized("Enabled") : featureSettingsLocalized("Disabled")
            )
        )
        return pills
    }

    var notePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(
                title: featureSettingsLocalized("Trigger"),
                value: shortSummary(
                    HotkeyPreference.displayString(
                        for: featureSettings.transcription.notes.triggerShortcut.hotkey,
                        distinguishModifierSides: false
                    )
                )
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Model"),
                value: shortSummary(llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID))
            )
        ]
    }

    var translationPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.translation.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Model"), value: shortSummary(translationSelectionSummary(featureSettings.translation.modelSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Target"), value: featureSettings.translation.targetLanguage.title)
        ]
    }

    var rewritePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.rewrite.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("LLM"), value: shortSummary(llmSelectionSummary(featureSettings.rewrite.llmSelectionID)))
        ]
    }

    var meetingPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.meeting.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Summary"), value: shortSummary(llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID)))
        ]
    }

    func shortSummary(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 28 else { return value }
        return String(value.prefix(25)) + "..."
    }

    @ViewBuilder
    func featurePage<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        pills: [FeatureSummaryPill],
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FeatureHeroCard(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    pills: pills
                )

                content()
            }
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .background(SettingsUIStyle.groupedFillColor.opacity(0.001))
    }

    var transcriptionLLMEnabledBinding: Binding<Bool> {
        binding(
            get: { featureSettings.transcription.llmEnabled },
            set: { featureSettings.transcription.llmEnabled = $0 }
        )
    }

    @ViewBuilder
    var noteObsidianSyncSection: some View {
        FeatureEmbeddedFieldGroup {
            FeatureToggleRow(
                title: featureSettingsLocalized("Enable Obsidian Sync"),
                detail: featureSettingsLocalized("Export Voxt notes into an Obsidian vault by writing Markdown files directly into the selected folder."),
                isOn: binding(
                    get: { featureSettings.transcription.notes.obsidianSync.enabled },
                    set: { featureSettings.transcription.notes.obsidianSync.enabled = $0 }
                ),
                isEmbedded: true
            )

            if featureSettings.transcription.notes.obsidianSync.enabled {
                FeatureDirectorySelectionRow(
                    title: featureSettingsLocalized("Vault Folder"),
                    detail: featureSettingsLocalized("Choose the Obsidian vault root folder that should receive exported Voxt notes."),
                    path: featureSettings.transcription.notes.obsidianSync.vaultPath.isEmpty
                        ? featureSettingsLocalized("Not configured")
                        : featureSettings.transcription.notes.obsidianSync.vaultPath,
                    buttonTitle: featureSettingsLocalized("Choose"),
                    action: chooseObsidianVaultDirectory,
                    isEmbedded: true
                )

                FeatureInlineTextFieldRow(
                    title: featureSettingsLocalized("Target Folder"),
                    detail: featureSettingsLocalized("Choose where inside the vault Voxt should write exported notes."),
                    text: binding(
                        get: { featureSettings.transcription.notes.obsidianSync.relativeFolder },
                        set: { featureSettings.transcription.notes.obsidianSync.relativeFolder = $0 }
                    ),
                    placeholder: "Voxt",
                    width: 230,
                    isEmbedded: true
                )

                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Grouping Mode"),
                    detail: featureSettingsLocalized("Choose how exported notes are organized inside Obsidian."),
                    isEmbedded: true
                ) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.transcription.notes.obsidianSync.groupingMode },
                            set: { featureSettings.transcription.notes.obsidianSync.groupingMode = $0 }
                        ),
                        options: ObsidianNoteGroupingMode.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: featureSettings.transcription.notes.obsidianSync.groupingMode.title,
                        width: 220
                    )
                }
            }
        }
    }

    @ViewBuilder
    var noteRemindersSyncSection: some View {
        FeatureEmbeddedFieldGroup {
            FeatureToggleRow(
                title: featureSettingsLocalized("Enable Reminders Sync"),
                detail: featureSettingsLocalized("Sync Voxt notes into Apple Reminders by creating and updating reminders in the selected list."),
                isOn: binding(
                    get: { featureSettings.transcription.notes.remindersSync.enabled },
                    set: { featureSettings.transcription.notes.remindersSync.enabled = $0 }
                ),
                isEmbedded: true
            )

            if featureSettings.transcription.notes.remindersSync.enabled {
                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Target List"),
                    detail: featureSettingsLocalized("Choose the Reminders list that should receive synced Voxt notes."),
                    isEmbedded: true
                ) {
                    SettingsSelectionButton(width: 220, action: presentRemindersListSelector) {
                        Text(selectedRemindersListTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }
}

private extension ObsidianNoteGroupingMode {
    var title: String {
        switch self {
        case .session:
            return featureSettingsLocalized("Session")
        case .daily:
            return featureSettingsLocalized("Daily")
        case .file:
            return featureSettingsLocalized("Single Note File")
        }
    }
}
