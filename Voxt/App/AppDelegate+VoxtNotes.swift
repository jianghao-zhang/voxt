import Foundation
import AppKit
import Carbon

extension AppDelegate {
    enum TranscriptionCaptureSessionMode {
        case standard
        case noteSession
    }

    private enum VoxtNoteTitleModel {
        case appleIntelligence
        case customLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

    func configureVoxtNoteSessionRuntimeStateForNewRecording() {
        transcriptionCaptureSessionMode = .standard
        liveTranscriptSegmentationState.reset()
        overlayState.setTranscribedTextTransformer { [weak self] rawText in
            self?.resolvedLiveTranscriptDisplayText(from: rawText) ?? rawText
        }
    }

    func resetVoxtNoteSessionRuntimeState() {
        transcriptionCaptureSessionMode = .standard
        liveTranscriptSegmentationState.reset()
        overlayState.setTranscribedTextTransformer(nil)
    }

    func shouldHandleLiveTranscriptNoteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return false }
        guard noteFeatureSettings.enabled else { return false }
        let shortcut = noteFeatureSettings.triggerShortcut.hotkey
        guard event.keyCode == shortcut.keyCode else { return false }
        let modifiers = event.modifierFlags.intersection(.hotkeyRelevant)
        guard modifiers == shortcut.modifiers else { return false }
        guard isSessionActive, sessionOutputMode == .transcription else { return false }
        guard overlayState.displayMode != .answer else { return false }
        return isCurrentTranscriptionCaptureLive
    }

    @discardableResult
    func captureLiveTranscriptNoteIfPossible(reason: String) -> Bool {
        guard noteFeatureSettings.enabled else { return false }
        guard isSessionActive, sessionOutputMode == .transcription else { return false }
        let rawText = currentSessionRawTranscribedText()
        let capturedText = liveTranscriptSegmentationState.freezeCurrentSegment(
            using: rawText,
            markerLabel: voxtNoteBoundaryMarkerLabel()
        )
            ?? overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            VoxtLog.info("Voxt note capture skipped because current transcript tail is empty. reason=\(reason)")
            return false
        }

        transcriptionCaptureSessionMode = .noteSession
        if noteFeatureSettings.soundEnabled {
            interactionSoundPlayer.playNote(preset: noteFeatureSettings.soundPreset)
        }
        appendVoxtNote(text: trimmedText, sessionID: activeRecordingSessionID)
        refreshVoxtNoteTranscriptDisplay()
        VoxtLog.info("Voxt note captured. reason=\(reason), characters=\(trimmedText.count)")
        return true
    }

    @discardableResult
    func captureTrailingVoxtNoteIfNeeded(finalRawText: String) -> Bool {
        guard transcriptionCaptureSessionMode == .noteSession else { return false }
        let trimmedFinalText = finalRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinalText.isEmpty else { return false }

        let capturedText = liveTranscriptSegmentationState.freezeCurrentSegment(using: trimmedFinalText)
        let trimmedCapturedText = capturedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCapturedText.isEmpty else {
            refreshVoxtNoteTranscriptDisplay()
            return false
        }

        appendVoxtNote(text: trimmedCapturedText, sessionID: activeRecordingSessionID)
        refreshVoxtNoteTranscriptDisplay()
        VoxtLog.info("Voxt note trailing segment captured at session end. characters=\(trimmedCapturedText.count)")
        return true
    }

    func refreshVoxtNoteTranscriptDisplay() {
        overlayState.refreshDisplayedTranscribedText()
    }

    var isCurrentTranscriptionNoteSessionActive: Bool {
        transcriptionCaptureSessionMode == .noteSession
    }

    private var isCurrentTranscriptionCaptureLive: Bool {
        guard recordingStoppedAt == nil else { return false }
        switch transcriptionEngine {
        case .dictation:
            return speechTranscriber.isRecording
        case .mlxAudio:
            return mlxTranscriber?.isRecording == true
        case .whisperKit:
            return whisperTranscriber?.isRecording == true
        case .remote:
            return remoteASRTranscriber.isRecording
        }
    }

    private func resolvedLiveTranscriptDisplayText(from rawText: String) -> String {
        guard isSessionActive, sessionOutputMode == .transcription else {
            return rawText
        }
        guard transcriptionCaptureSessionMode == .noteSession else {
            return rawText
        }
        return liveTranscriptSegmentationState.displayText(for: rawText)
    }

    func currentSessionRawTranscribedText() -> String {
        switch transcriptionEngine {
        case .dictation:
            return speechTranscriber.transcribedText
        case .mlxAudio:
            return mlxTranscriber?.transcribedText ?? ""
        case .whisperKit:
            return whisperTranscriber?.transcribedText ?? ""
        case .remote:
            return remoteASRTranscriber.transcribedText
        }
    }

    private func appendVoxtNote(text: String, sessionID: UUID) {
        let fallbackTitle = VoxtNoteTitleSupport.fallbackTitle(from: text)
        let resolvedTitleModel = resolvedVoxtNoteTitleModel()
        let initialState: NoteTitleGenerationState = resolvedTitleModel == nil ? .fallback : .pending

        guard let item = noteStore.append(
            sessionID: sessionID,
            text: text,
            title: fallbackTitle,
            titleGenerationState: initialState
        ) else {
            return
        }

        noteWindowManager.show()

        guard let resolvedTitleModel else { return }
        Task { @MainActor [weak self] in
            await self?.generateVoxtNoteTitle(
                for: item.id,
                text: item.text,
                fallbackTitle: fallbackTitle,
                model: resolvedTitleModel
            )
        }
    }

    private func generateVoxtNoteTitle(
        for noteID: UUID,
        text: String,
        fallbackTitle: String,
        model: VoxtNoteTitleModel
    ) async {
        do {
            let generatedTitle = try await runVoxtNoteTitlePrompt(
                voxtNoteTitlePrompt(for: text),
                model: model
            )
            let normalizedTitle = VoxtNoteTitleSupport.normalizedGeneratedTitle(generatedTitle)
            let resolvedTitle = normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle
            let resolvedState: NoteTitleGenerationState = normalizedTitle.isEmpty ? .fallback : .generated
            _ = noteStore.updateTitle(resolvedTitle, state: resolvedState, for: noteID)
            VoxtLog.info(
                "Voxt note title generated. noteID=\(noteID.uuidString), state=\(resolvedState.rawValue), titleChars=\(resolvedTitle.count)"
            )
        } catch {
            _ = noteStore.updateTitle(fallbackTitle, state: .fallback, for: noteID)
            VoxtLog.warning("Voxt note title generation failed. noteID=\(noteID.uuidString), error=\(error.localizedDescription)")
        }
    }

    private func resolvedVoxtNoteTitleModel() -> VoxtNoteTitleModel? {
        switch noteFeatureSettings.titleModelSelectionID.textSelection {
        case .appleIntelligence:
            guard let enhancer else { return nil }
            if #available(macOS 26.0, *) {
                guard TextEnhancer.isAvailable else { return nil }
                _ = enhancer
                return .appleIntelligence
            }
            return nil
        case .localLLM(let repo):
            guard customLLMManager.isModelDownloaded(repo: repo) else { return nil }
            return .customLLM(repo: repo)
        case .remoteLLM(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured, configuration.hasUsableModel else { return nil }
            return .remoteLLM(provider: provider, configuration: configuration)
        case .none:
            return nil
        }
    }

    private func runVoxtNoteTitlePrompt(
        _ prompt: String,
        model: VoxtNoteTitleModel
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        switch model {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "Voxt.NoteTitle",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(userPrompt: trimmedPrompt)
            }
            throw NSError(
                domain: "Voxt.NoteTitle",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            return try await customLLMManager.enhance(userPrompt: trimmedPrompt, repo: repo)
        case .remoteLLM(let provider, let configuration):
            return try await RemoteLLMRuntimeClient().enhance(
                userPrompt: trimmedPrompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func voxtNoteTitlePrompt(for text: String) -> String {
        """
        You are Voxt's note title generator.

        Generate a very short plain-text title for the note below.

        Rules:
        1. Reply in the user's main language.
        2. Return one line only.
        3. Keep it concise and specific.
        4. Avoid quotes, numbering, markdown, or extra explanation.
        5. Prefer 4-8 words, or under 20 Chinese characters.

        User main language: \(userMainLanguagePromptValue)

        Note text:
        \(text)

        Return only the title.
        """
    }

    private func voxtNoteBoundaryMarkerLabel() -> String {
        guard let recordingStartedAt else { return "00:00" }
        let elapsed = max(0, Int(Date().timeIntervalSince(recordingStartedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
