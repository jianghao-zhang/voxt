import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

private func localizedKey(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(AppLocalization.localizedString(key))
}

struct FeatureSettingsView: View {
    let selectedTab: FeatureSettingsTab
    let navigationRequest: SettingsNavigationRequest?
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager

    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) private var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @State private var featureSettings = FeatureSettingsStore.load()
    @State private var selectorSheet: FeatureModelSelectorSheet?
    @State private var interactionSoundPlayer = InteractionSoundPlayer()

    var body: some View {
        Group {
            switch selectedTab {
            case .transcription:
                transcriptionContent
            case .note:
                noteContent
            case .translation:
                translationContent
            case .rewrite:
                rewriteContent
            case .appEnhancement:
                AppEnhancementSettingsView(navigationRequest: navigationRequest)
            case .meeting:
                meetingContent
            }
        }
        .sheet(item: $selectorSheet) { sheet in
            FeatureModelSelectorDialog(
                title: sheet.title,
                entries: selectorEntries(for: sheet),
                selectedID: selectedSelectionID(for: sheet),
                onSelect: { selectionID in
                    applySelection(selectionID, for: sheet)
                }
            )
        }
        .onAppear(perform: reloadFeatureSettings)
        .onChange(of: featureSettingsRaw) { _, _ in
            reloadFeatureSettings()
        }
        .id(interfaceLanguageRaw)
    }

    private var transcriptionContent: some View {
        featurePage(
            title: localized("Transcription"),
            subtitle: localized("Choose the speech model used for standard transcription, and optionally layer an LLM cleanup pass on top."),
            icon: "waveform.and.mic",
            pills: transcriptionPills
        ) {
            FeatureSettingsCard(title: localized("Model Pipeline")) {
                FeatureSettingSection(title: localized("Speech Recognition"), detail: localized("This model handles the first-pass transcript.")) {
                    FeatureSelectorRow(
                        title: localized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.transcription.asrSelectionID),
                        action: { selectorSheet = .transcriptionASR }
                    )
                }

                FeatureToggleRow(
                    title: localized("Enable LLM Enhancement"),
                    detail: localized("Use a second language model pass to clean punctuation, structure, and readability."),
                    isOn: transcriptionLLMEnabledBinding
                )

                FeatureToggleRow(
                    title: localized("Enable Meeting"),
                    detail: localized("Turn on the dedicated meeting workflow, shortcut, overlay, and meeting-specific model settings."),
                    isOn: binding(
                        get: { featureSettings.meeting.enabled },
                        set: { featureSettings.meeting.enabled = $0 }
                    )
                )

                FeatureToggleRow(
                    title: localized("Enable Notes"),
                    detail: localized("Add segmented notes during transcription. Once enabled, Notes appears in the Feature menu and supports a dedicated trigger key."),
                    isOn: binding(
                        get: { featureSettings.transcription.notes.enabled },
                        set: { featureSettings.transcription.notes.enabled = $0 }
                    )
                )

                if featureSettings.transcription.llmEnabled {
                    FeatureSettingSection(title: localized("Text Enhancement"), detail: localized("Only configured and installed models can be selected here.")) {
                        FeatureSelectorRow(
                            title: localized("LLM Model"),
                            value: llmSelectionSummary(featureSettings.transcription.llmSelectionID),
                            action: { selectorSheet = .transcriptionLLM }
                        )
                        FeaturePromptSection(
                            title: localized("Enhancement Prompt"),
                            text: binding(
                                get: { featureSettings.transcription.prompt },
                                set: { featureSettings.transcription.prompt = $0 }
                            ),
                            defaultText: AppPreferenceKey.defaultEnhancementPrompt,
                            variables: ModelSettingsPromptVariables.enhancement
                        )
                    }
                }

                if featureSettings.transcription.notes.enabled {
                    FeatureHintBanner(
                        title: localized("Notes"),
                        detail: localized("Notes configuration moved here after transcription-level enablement.")
                    )
                }
            }
        }
    }

    private var noteContent: some View {
        featurePage(
            title: localized("Notes"),
            subtitle: localized("Cut a live transcription into separate notes without stopping the recording session. Notes stay in their own floating window and each one gets a short AI title."),
            icon: "note.text",
            pills: notePills
        ) {
            FeatureSettingsCard(title: localized("Notes Workflow")) {
                FeatureNoteShortcutRow(
                    title: localized("Note Trigger"),
                    detail: localized("Use this key while a live transcription session is recording to save the current transcript tail as a note and insert a note marker into the OverLazy preview."),
                    shortcut: binding(
                        get: { featureSettings.transcription.notes.triggerShortcut },
                        set: { featureSettings.transcription.notes.triggerShortcut = $0 }
                    )
                )

                FeatureSettingSection(title: localized("Title Generation"), detail: localized("This model generates the short floating-card title for each saved note.")) {
                    FeatureSelectorRow(
                        title: localized("Note Title Model"),
                        value: llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID),
                        action: { selectorSheet = .transcriptionNoteTitle }
                    )
                }

                FeatureToggleRow(
                    title: localized("Note Audio"),
                    detail: localized("Play a short reminder sound each time the note trigger is pressed during a live transcription session."),
                    isOn: binding(
                        get: { featureSettings.transcription.notes.soundEnabled },
                        set: { featureSettings.transcription.notes.soundEnabled = $0 }
                    )
                )

                if featureSettings.transcription.notes.soundEnabled {
                    FeatureInlinePickerRow(
                        title: localized("Note Sound Preset"),
                        detail: localized("Choose the reminder sound used when a note is captured, and preview it here.")
                    ) {
                        HStack(spacing: 8) {
                            SettingsMenuPicker(
                                selection: binding(
                                    get: { featureSettings.transcription.notes.soundPreset },
                                    set: { featureSettings.transcription.notes.soundPreset = $0 }
                                ),
                                options: InteractionSoundPreset.allCases.map { preset in
                                    SettingsMenuOption(value: preset, title: preset.title)
                                },
                                selectedTitle: featureSettings.transcription.notes.soundPreset.title,
                                width: 220
                            )

                            Button(localized("Try Sound")) {
                                interactionSoundPlayer.playPreview(preset: featureSettings.transcription.notes.soundPreset)
                            }
                            .buttonStyle(SettingsPillButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var translationContent: some View {
        featurePage(
            title: localized("Translation"),
            subtitle: localized("Configure the speech path, translation engine, target language, and prompt behavior for translation mode."),
            icon: "globe",
            pills: translationPills
        ) {
            FeatureSettingsCard(title: localized("Translation Flow")) {
                FeatureSettingSection(title: localized("Speech Recognition"), detail: localized("Choose the ASR model that feeds the translation pipeline.")) {
                    FeatureSelectorRow(
                        title: localized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.translation.asrSelectionID),
                        action: { selectorSheet = .translationASR }
                    )
                }

                FeatureSettingSection(title: localized("Translation Model"), detail: localized("Select an LLM or use Whisper direct translation when the ASR path supports it.")) {
                    FeatureSelectorRow(
                        title: localized("Translation Model"),
                        value: translationSelectionSummary(featureSettings.translation.modelSelectionID),
                        action: { selectorSheet = .translationModel }
                    )
                }

                FeatureInlinePickerRow(title: localized("Target Language"), detail: localized("Move the shared translation language setting here so the behavior stays feature-local.")) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.translation.targetLanguage },
                            set: { featureSettings.translation.targetLanguageRawValue = $0.rawValue }
                        ),
                        options: TranslationTargetLanguage.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: featureSettings.translation.targetLanguage.title,
                        width: 220
                    )
                }

                FeatureToggleRow(
                    title: localized("Replace Selected Text"),
                    detail: localized("Run translation directly against the current selected text when the translation shortcut is triggered."),
                    isOn: binding(
                        get: { featureSettings.translation.replaceSelectedText },
                        set: { featureSettings.translation.replaceSelectedText = $0 }
                    )
                )

                if featureSettings.translation.modelSelectionID.translationSelection != .whisperDirectTranslate {
                    FeatureSettingSection(title: localized("Prompt"), detail: localized("Prompt controls are shown only when the selected translation model supports prompt-based generation.")) {
                        FeaturePromptSection(
                            title: localized("Translation Prompt"),
                            text: binding(
                                get: { featureSettings.translation.prompt },
                                set: { featureSettings.translation.prompt = $0 }
                            ),
                            defaultText: AppPreferenceKey.defaultTranslationPrompt,
                            variables: ModelSettingsPromptVariables.translation
                        )
                    }
                } else {
                    FeatureHintBanner(
                        title: localized("Whisper Direct Translation"),
                        detail: localized("Prompt editing is hidden here because Whisper direct translation does not consume a text prompt.")
                    )
                }
            }
        }
    }

    private var rewriteContent: some View {
        featurePage(
            title: localized("Rewrite"),
            subtitle: localized("Set the ASR and text model pairing used for rewrite mode, then decide whether app-aware enhancement is enabled."),
            icon: "text.badge.star",
            pills: rewritePills
        ) {
            FeatureSettingsCard(title: localized("Rewrite Flow")) {
                FeatureSettingSection(title: localized("Speech Recognition"), detail: localized("Choose the speech model that feeds rewrite mode.")) {
                    FeatureSelectorRow(
                        title: localized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.rewrite.asrSelectionID),
                        action: { selectorSheet = .rewriteASR }
                    )
                }

                FeatureSettingSection(title: localized("Rewrite Model"), detail: localized("Pick the text model used to rewrite, rephrase, or clean captured content.")) {
                    FeatureSelectorRow(
                        title: localized("LLM Model"),
                        value: llmSelectionSummary(featureSettings.rewrite.llmSelectionID),
                        action: { selectorSheet = .rewriteLLM }
                    )
                }

                FeatureSettingSection(title: localized("Prompt"), detail: localized("Prompt templates stay local to rewrite mode and no longer live in the shared model page.")) {
                    FeaturePromptSection(
                        title: localized("Rewrite Prompt"),
                        text: binding(
                            get: { featureSettings.rewrite.prompt },
                            set: { featureSettings.rewrite.prompt = $0 }
                        ),
                        defaultText: AppPreferenceKey.defaultRewritePrompt,
                        variables: ModelSettingsPromptVariables.rewrite
                    )
                }

                FeatureToggleRow(
                    title: localized("Enable App Enhancement"),
                    detail: localized("When enabled, the dedicated App Enhancement submenu becomes available in Feature mode."),
                    isOn: binding(
                        get: { featureSettings.rewrite.appEnhancementEnabled },
                        set: { featureSettings.rewrite.appEnhancementEnabled = $0 }
                    )
                )
                }
        }
    }

    private var meetingContent: some View {
        featurePage(
            title: localized("Meeting"),
            subtitle: localized("Meeting mode now owns its own ASR, summary model, prompt, and realtime translation settings."),
            icon: "person.2.crop.square.stack",
            pills: meetingPills
        ) {
            FeatureSettingsCard(title: localized("Meeting Workflow")) {
                FeatureSettingSection(title: localized("Speech Recognition"), detail: localized("Choose the ASR pipeline used only for meeting mode.")) {
                    FeatureSelectorRow(
                        title: localized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.meeting.asrSelectionID),
                        action: { selectorSheet = .meetingASR }
                    )
                }

                FeatureSettingSection(title: localized("Summary Model"), detail: localized("This model is used for meeting summaries and is independent from transcription or rewrite models.")) {
                    FeatureSelectorRow(
                        title: localized("Summary Model"),
                        value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID),
                        action: { selectorSheet = .meetingSummary }
                    )
                }

                FeatureToggleRow(
                    title: localized("Auto-generate Summary"),
                    detail: localized("Generate the meeting summary automatically when the session completes."),
                    isOn: binding(
                        get: { featureSettings.meeting.summaryAutoGenerate },
                        set: { featureSettings.meeting.summaryAutoGenerate = $0 }
                    )
                )

                FeatureToggleRow(
                    title: localized("Realtime Translation"),
                    detail: localized("Keep a live translated view during meetings using the meeting-specific translation target."),
                    isOn: binding(
                        get: { featureSettings.meeting.realtimeTranslateEnabled },
                        set: { featureSettings.meeting.realtimeTranslateEnabled = $0 }
                    )
                )

                FeatureInlinePickerRow(title: localized("Realtime Target"), detail: localized("Only used when realtime translation is enabled.")) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.meeting.realtimeTargetLanguage ?? .english },
                            set: { featureSettings.meeting.realtimeTargetLanguageRawValue = $0.rawValue }
                        ),
                        options: TranslationTargetLanguage.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: (featureSettings.meeting.realtimeTargetLanguage ?? .english).title,
                        width: 220
                    )
                }

                FeatureToggleRow(
                    title: localized("Show Overlay In Screen Sharing"),
                    detail: localized("Keep the meeting overlay visible when sharing the screen. Turn this off when the overlay should stay private."),
                    isOn: binding(
                        get: { featureSettings.meeting.showOverlayInScreenShare },
                        set: { featureSettings.meeting.showOverlayInScreenShare = $0 }
                    )
                )

                FeatureSettingSection(title: localized("Summary Prompt"), detail: localized("Use prompt variables to shape the meeting summary format and focus.")) {
                    FeaturePromptSection(
                        title: localized("Summary Prompt"),
                        text: binding(
                            get: { featureSettings.meeting.summaryPrompt },
                            set: { featureSettings.meeting.summaryPrompt = $0 }
                        ),
                        defaultText: AppPreferenceKey.defaultMeetingSummaryPrompt,
                        variables: MeetingSummarySupport.promptTemplateVariables.map {
                            PromptTemplateVariableDescriptor(token: $0, tipKey: "Template tip \($0)")
                        }
                    )
                }
            }
        }
    }

    private var transcriptionPills: [FeatureSummaryPill] {
        var pills = [
            FeatureSummaryPill(title: localized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.transcription.asrSelectionID)))
        ]
        pills.append(
            FeatureSummaryPill(
                title: localized("LLM"),
                value: featureSettings.transcription.llmEnabled
                    ? shortSummary(llmSelectionSummary(featureSettings.transcription.llmSelectionID))
                    : localized("Off")
            )
        )
        return pills
    }

    private var notePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(
                title: localized("Trigger"),
                value: shortSummary(
                    HotkeyPreference.displayString(
                        for: featureSettings.transcription.notes.triggerShortcut.hotkey,
                        distinguishModifierSides: false
                    )
                )
            ),
            FeatureSummaryPill(
                title: localized("Model"),
                value: shortSummary(llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID))
            )
        ]
    }

    private var translationPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: localized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.translation.asrSelectionID))),
            FeatureSummaryPill(title: localized("Model"), value: shortSummary(translationSelectionSummary(featureSettings.translation.modelSelectionID))),
            FeatureSummaryPill(title: localized("Target"), value: featureSettings.translation.targetLanguage.title)
        ]
    }

    private var rewritePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: localized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.rewrite.asrSelectionID))),
            FeatureSummaryPill(title: localized("LLM"), value: shortSummary(llmSelectionSummary(featureSettings.rewrite.llmSelectionID))),
            FeatureSummaryPill(title: localized("App"), value: featureSettings.rewrite.appEnhancementEnabled ? localized("Enabled") : localized("Disabled"))
        ]
    }

    private var meetingPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: localized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.meeting.asrSelectionID))),
            FeatureSummaryPill(title: localized("Summary"), value: shortSummary(llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID)))
        ]
    }

    private func shortSummary(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 28 else { return value }
        return String(value.prefix(25)) + "..."
    }

    @ViewBuilder
    private func featurePage<Content: View>(
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

    private var transcriptionLLMEnabledBinding: Binding<Bool> {
        binding(
            get: { featureSettings.transcription.llmEnabled },
            set: { featureSettings.transcription.llmEnabled = $0 }
        )
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: get,
            set: { newValue in
                set(newValue)
                FeatureSettingsStore.save(featureSettings, defaults: .standard)
                reloadFeatureSettings()
            }
        )
    }

    private func reloadFeatureSettings() {
        featureSettings = FeatureSettingsStore.load(defaults: .standard)
    }

    private var selectorBuilder: FeatureModelCatalogBuilder {
        FeatureModelCatalogBuilder(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager,
            featureSettings: featureSettings,
            remoteASRProviderConfigurationsRaw: remoteASRProviderConfigurationsRaw,
            remoteLLMProviderConfigurationsRaw: remoteLLMProviderConfigurationsRaw,
            appleIntelligenceAvailable: appleIntelligenceAvailable,
            primaryUserLanguageCode: selectedUserLanguageCodes.first
        )
    }

    private var selectedUserLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    private func selectedSelectionID(for sheet: FeatureModelSelectorSheet) -> FeatureModelSelectionID {
        switch sheet {
        case .transcriptionASR:
            return featureSettings.transcription.asrSelectionID
        case .transcriptionLLM:
            return featureSettings.transcription.llmSelectionID
        case .transcriptionNoteTitle:
            return featureSettings.transcription.notes.titleModelSelectionID
        case .translationASR:
            return featureSettings.translation.asrSelectionID
        case .translationModel:
            return featureSettings.translation.modelSelectionID
        case .rewriteASR:
            return featureSettings.rewrite.asrSelectionID
        case .rewriteLLM:
            return featureSettings.rewrite.llmSelectionID
        case .meetingASR:
            return featureSettings.meeting.asrSelectionID
        case .meetingSummary:
            return featureSettings.meeting.summaryModelSelectionID
        }
    }

    private func applySelection(_ selectionID: FeatureModelSelectionID, for sheet: FeatureModelSelectorSheet) {
        FeatureSettingsStore.update(defaults: .standard) { settings in
            switch sheet {
            case .transcriptionASR:
                settings.transcription.asrSelectionID = selectionID
            case .transcriptionLLM:
                settings.transcription.llmSelectionID = selectionID
            case .transcriptionNoteTitle:
                settings.transcription.notes.titleModelSelectionID = selectionID
            case .translationASR:
                settings.translation.asrSelectionID = selectionID
            case .translationModel:
                settings.translation.modelSelectionID = selectionID
            case .rewriteASR:
                settings.rewrite.asrSelectionID = selectionID
            case .rewriteLLM:
                settings.rewrite.llmSelectionID = selectionID
            case .meetingASR:
                settings.meeting.asrSelectionID = selectionID
            case .meetingSummary:
                settings.meeting.summaryModelSelectionID = selectionID
            }
        }
        reloadFeatureSettings()
    }

    private func selectorEntries(for sheet: FeatureModelSelectorSheet) -> [FeatureModelSelectorEntry] {
        selectorBuilder.entries(for: sheet)
    }

    private func asrSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.asrSelectionSummary(selectionID)
    }

    private func llmSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.llmSelectionSummary(selectionID)
    }

    private func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.translationSelectionSummary(selectionID)
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

}
