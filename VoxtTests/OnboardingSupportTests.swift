import XCTest
@testable import Voxt

final class OnboardingSupportTests: XCTestCase {
    func testTranscriptionPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .dictation,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testTranscriptionPermissionsIncludeSystemAudioWhenMuteEnabled() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: true,
                meetingNotesEnabled: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testMeetingPermissionsOnlyAppearWhenMeetingModeEnabled() {
        let disabledPermissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .meeting,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: false
            )
        )
        let enabledPermissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .meeting,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .remote,
                muteSystemAudioWhileRecording: false,
                meetingNotesEnabled: true
            )
        )

        XCTAssertTrue(disabledPermissions.isEmpty)
        XCTAssertEqual(
            enabledPermissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testNonRecordingStepsDoNotRequirePermissions() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: true,
            meetingNotesEnabled: true
        )

        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .language, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .model, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .translation, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .appEnhancement, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .finish, context: context).isEmpty)
    }

    func testFeatureSelectionResolverMapsASRSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .mlxAudio,
                mlxModelRepo: "mlx-community/whisper-large-v3-turbo-4bit",
                whisperModelID: "openai_whisper-tiny",
                remoteASRProvider: .doubaoASR
            ),
            .mlx("mlx-community/whisper-large-v3-turbo-4bit")
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .remote,
                mlxModelRepo: "",
                whisperModelID: "",
                remoteASRProvider: .doubaoASR
            ),
            .remoteASR(.doubaoASR)
        )
    }

    func testFeatureSelectionResolverMapsLLMSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .local,
                localLLMRepo: "mlx-community/Qwen3-4B-4bit",
                remoteLLMProvider: .openAI
            ),
            .localLLM("mlx-community/Qwen3-4B-4bit")
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .system,
                localLLMRepo: "",
                remoteLLMProvider: .openAI
            ),
            .appleIntelligence
        )
    }

    func testFeatureSelectionResolverUsesWhisperDirectTranslateForAppleIntelligencePlusWhisper() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .whisper("openai_whisper-large-v3"),
            existingSelection: .remoteLLM(.openAI),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .whisperDirectTranslate)
    }

    func testFeatureSelectionResolverPreservesExistingTranslationSelectionWhenCompatible() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .mlx("mlx-community/whisper-large-v3-turbo-4bit"),
            existingSelection: .remoteLLM(.openAI),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .remoteLLM(.openAI))
    }
}
