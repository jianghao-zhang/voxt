import XCTest
@testable import Voxt

@MainActor
final class MLXModelManagerTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyReposToCurrentIdentifiers() {
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/GLM-ASR-Nano-4bit"),
            "mlx-community/GLM-ASR-Nano-2512-4bit"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"),
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
        )
        XCTAssertEqual(
            MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
    }

    func testRealtimeCapableModelRepoTreatsAllVoxtralQuantizationsAsRealtime() {
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit"))
        XCTAssertTrue(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"))
        XCTAssertFalse(MLXModelManager.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"))
    }

    func testTranscriptionBehaviorUsesFinalizationOnlyModeForFireRed() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")

        XCTAssertEqual(behavior.correctionMode, .finalizationOnly)
        XCTAssertFalse(behavior.runsIntermediateCorrections)
        XCTAssertFalse(behavior.allowsQuickStopPass)
        XCTAssertTrue(behavior.preloadsOnRecordingStart)
    }

    func testTranscriptionBehaviorUsesIncrementalModeForDefaultModels() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")

        XCTAssertEqual(behavior.correctionMode, .incremental)
        XCTAssertTrue(behavior.runsIntermediateCorrections)
        XCTAssertTrue(behavior.allowsQuickStopPass)
        XCTAssertTrue(behavior.preloadsOnRecordingStart)
    }

    func testIntermediateCorrectionDecisionSkipsFinalizationOnlyBehavior() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")

        XCTAssertNil(
            MLXTranscriptionPlanning.intermediateCorrectionDecision(
                sampleCount: 16000 * 8,
                sampleRate: 16000,
                nextCorrectionAtSeconds: 6,
                behavior: behavior,
                firstCorrectionMinimumSeconds: 3.5,
                contextWindowSeconds: 18
            )
        )
    }

    func testIntermediateCorrectionDecisionReturnsContextWindowForIncrementalBehavior() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")

        let decision = MLXTranscriptionPlanning.intermediateCorrectionDecision(
            sampleCount: 16000 * 8,
            sampleRate: 16000,
            nextCorrectionAtSeconds: 6,
            behavior: behavior,
            firstCorrectionMinimumSeconds: 3.5,
            contextWindowSeconds: 18
        )

        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.elapsedSeconds ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(decision?.contextSampleCount, 16000 * 18)
    }

    func testFinalizationPlanDisablesQuickPassForFireRed() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/FireRedASR2")
        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: 16000 * 30,
            sampleRate: 16000,
            behavior: behavior,
            quickPassMinimumDurationSeconds: 14,
            quickPassContextWindowSeconds: 30
        )

        XCTAssertEqual(plan.durationSeconds, 30, accuracy: 0.0001)
        XCTAssertFalse(plan.shouldRunQuickPass)
        XCTAssertNil(plan.quickPassSampleCount)
    }

    func testFinalizationPlanUsesQuickPassForLongIncrementalAudio() {
        let behavior = MLXModelManager.transcriptionBehavior(for: "mlx-community/Qwen3-ASR-0.6B-4bit")
        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: 16000 * 30,
            sampleRate: 16000,
            behavior: behavior,
            quickPassMinimumDurationSeconds: 14,
            quickPassContextWindowSeconds: 30
        )

        XCTAssertEqual(plan.durationSeconds, 30, accuracy: 0.0001)
        XCTAssertTrue(plan.shouldRunQuickPass)
        XCTAssertEqual(plan.quickPassSampleCount, 16000 * 30)
    }

    func testAvailableModelsIncludeLatestSupportedSTTRepos() {
        let modelIDs = Set(MLXModelManager.availableModels.map(\.id))

        XCTAssertTrue(modelIDs.contains("mlx-community/parakeet-tdt-0.6b-v2"))
        XCTAssertTrue(modelIDs.contains("mlx-community/granite-4.0-1b-speech-5bit"))
        XCTAssertTrue(modelIDs.contains("mlx-community/FireRedASR2-AED-mlx"))
        XCTAssertTrue(modelIDs.contains("mlx-community/SenseVoiceSmall"))
    }

    func testCustomLLMBehaviorDisablesThinkingForQwen3Family() {
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-4B-4bit").disablesThinking)
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3-8B-4bit").disablesThinking)
        XCTAssertTrue(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Qwen3.5-4B-MLX-4bit").disablesThinking)
    }

    func testCustomLLMBehaviorLeavesOtherInstructionModelsUntouched() {
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2-1.5B-Instruct").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "Qwen/Qwen2.5-3B-Instruct").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/GLM-4-9B-0414-4bit").disablesThinking)
        XCTAssertFalse(CustomLLMModelBehaviorResolver.behavior(for: "mlx-community/Llama-3.2-3B-Instruct-4bit").disablesThinking)
    }

    func testCustomLLMNormalizeResultTextStripsThinkBlocksAndMarkers() {
        let output = """
        <think>
        reason
        </think>

        ```json
        {"resultText":"Hello"}
        ```
        """

        XCTAssertEqual(CustomLLMOutputSanitizer.normalizeResultText(output), #"{"resultText":"Hello"}"#)
        XCTAssertEqual(CustomLLMOutputSanitizer.normalizeResultText("<think>\n\n</think>\n\nHello"), "Hello")
    }
}
