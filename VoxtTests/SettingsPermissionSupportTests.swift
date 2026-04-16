import XCTest
@testable import Voxt

final class SettingsPermissionSupportTests: XCTestCase {
    private func makeFeatureSettings(
        transcriptionASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        translationASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        rewriteASR: FeatureModelSelectionID = .mlx(MLXModelManager.defaultModelRepo),
        meetingEnabled: Bool = false,
        meetingASR: FeatureModelSelectionID = .remoteASR(.doubaoASR)
    ) -> FeatureSettings {
        FeatureSettings(
            transcription: .init(
                asrSelectionID: transcriptionASR,
                llmEnabled: false,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: .init(
                asrSelectionID: translationASR,
                modelSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                targetLanguageRawValue: TranslationTargetLanguage.english.rawValue,
                prompt: AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: true
            ),
            rewrite: .init(
                asrSelectionID: rewriteASR,
                llmSelectionID: .localLLM(CustomLLMModelManager.defaultModelRepo),
                prompt: AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: false
            ),
            meeting: .init(
                enabled: meetingEnabled,
                asrSelectionID: meetingASR,
                summaryModelSelectionID: .remoteLLM(.openAI),
                summaryPrompt: AppPreferenceKey.defaultMeetingSummaryPrompt,
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: "",
                showOverlayInScreenShare: false
            )
        )
    }

    func testSidebarRequirementContextOnlyIncludesMeetingPermissionsWhenMeetingIsEnabled() {
        let disabledMeetingSettings = makeFeatureSettings()

        let disabledContext = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: disabledMeetingSettings
        )
        XCTAssertFalse(disabledContext.meetingNotesEnabled)

        var enabledMeetingSettings = disabledMeetingSettings
        enabledMeetingSettings.meeting.enabled = true
        let enabledContext = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: enabledMeetingSettings
        )
        XCTAssertTrue(enabledContext.meetingNotesEnabled)
    }

    func testSidebarPermissionsExcludeSystemAudioWhenMeetingAndMuteAreDisabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(meetingEnabled: false)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .accessibility, .inputMonitoring])
    }

    func testSidebarPermissionsIncludeSystemAudioWhenMeetingIsEnabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(meetingEnabled: true)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture])
    }

    func testSidebarPermissionsIncludeSystemAudioWhenMuteDuringRecordingIsEnabled() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: true,
            featureSettings: makeFeatureSettings(meetingEnabled: false)
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(permissions, [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture])
    }

    func testSidebarPermissionsIncludeSpeechRecognitionWhenFeatureUsesDictation() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(
                transcriptionASR: .dictation,
                meetingEnabled: false
            )
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testSidebarPermissionsIncludeSpeechRecognitionWhenMeetingUsesDictation() {
        let context = SettingsPermissionRequirementResolver.sidebarRequirementContext(
            selectedEngine: .remote,
            muteSystemAudioWhileRecording: false,
            featureSettings: makeFeatureSettings(
                meetingEnabled: true,
                meetingASR: .dictation
            )
        )

        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(context: context)

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition, .systemAudioCapture]
        )
    }

    func testRequiredPermissionsDoNotIncludeConditionalItemsWhenFeaturesAreDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring]
        )
    }

    func testRequiredPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .dictation,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testRequiredPermissionsIncludeSystemAudioWhenMeetingNotesAreEnabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: true,
                featureSettings: nil
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testRequiredPermissionsDoNotIncludeSystemAudioWhenMeetingFeatureIsDisabled() {
        let permissions = SettingsPermissionRequirementResolver.requiredPermissions(
            context: SettingsPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false,
                featureSettings: makeFeatureSettings(meetingEnabled: false)
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring]
        )
    }
}
