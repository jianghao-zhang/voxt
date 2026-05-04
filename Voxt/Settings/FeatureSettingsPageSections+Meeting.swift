import SwiftUI

extension FeatureSettingsView {
    var meetingContent: some View {
        featurePage(
            title: featureSettingsLocalized("Meeting"),
            subtitle: featureSettingsLocalized("Meeting mode now owns its own ASR, summary model, prompt, and realtime translation settings."),
            icon: "person.2.crop.square.stack",
            pills: meetingPills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Meeting Workflow")) {
                FeatureSettingSection(title: featureSettingsLocalized("Speech Recognition"), detail: featureSettingsLocalized("Choose the ASR pipeline used only for meeting mode.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.meeting.asrSelectionID),
                        action: { selectorSheet = .meetingASR }
                    )
                }

                FeatureSettingSection(title: featureSettingsLocalized("Summary Model"), detail: featureSettingsLocalized("This model is used for meeting summaries and is independent from transcription or rewrite models.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Summary Model"),
                        value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID),
                        action: { selectorSheet = .meetingSummary }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Auto-generate Summary"),
                    detail: featureSettingsLocalized("Generate the meeting summary automatically when the session completes."),
                    isOn: binding(
                        get: { featureSettings.meeting.summaryAutoGenerate },
                        set: { featureSettings.meeting.summaryAutoGenerate = $0 }
                    )
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Realtime Translation"),
                    detail: featureSettingsLocalized("Keep a live translated view during meetings using the meeting-specific translation target."),
                    isOn: binding(
                        get: { featureSettings.meeting.realtimeTranslateEnabled },
                        set: { featureSettings.meeting.realtimeTranslateEnabled = $0 }
                    )
                )

                FeatureInlinePickerRow(title: featureSettingsLocalized("Realtime Target"), detail: featureSettingsLocalized("Only used when realtime translation is enabled.")) {
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
                    title: featureSettingsLocalized("Show Overlay In Screen Sharing"),
                    detail: featureSettingsLocalized("Keep the meeting overlay visible when sharing the screen. Turn this off when the overlay should stay private."),
                    isOn: binding(
                        get: { featureSettings.meeting.showOverlayInScreenShare },
                        set: { featureSettings.meeting.showOverlayInScreenShare = $0 }
                    )
                )

                FeatureSettingSection(title: featureSettingsLocalized("Summary Prompt"), detail: featureSettingsLocalized("Use prompt variables to shape the meeting summary format and focus.")) {
                    FeaturePromptSection(
                        title: featureSettingsLocalized("Summary Prompt"),
                        text: promptBinding(
                            get: { featureSettings.meeting.summaryPrompt },
                            set: { featureSettings.meeting.summaryPrompt = $0 },
                            kind: .meetingSummary
                        ),
                        defaultText: AppPromptDefaults.text(for: .meetingSummary),
                        variables: MeetingSummarySupport.promptTemplateVariables.map {
                            PromptTemplateVariableDescriptor(token: $0, tipKey: "Template tip \($0)")
                        },
                        persistChanges: saveFeatureSettings
                    )
                }
            }
        }
    }
}
