import AppKit
import Foundation

extension AppDelegate {
    @MainActor
    private protocol SessionEndStage {
        var name: String { get }
        func run(delegate: AppDelegate)
    }

    private struct HideOverlayStage: SessionEndStage {
        var name: String { "hideOverlay" }

        func run(delegate: AppDelegate) {
            guard delegate.overlayState.displayMode != .answer else { return }
            delegate.overlayWindow.hide(animated: false)
        }
    }

    private struct RestoreSystemAudioStage: SessionEndStage {
        var name: String { "restoreSystemAudio" }

        func run(delegate: AppDelegate) {
            delegate.systemAudioMuteController.restoreSystemAudioIfNeeded()
        }
    }

    private struct PlayEndSoundStage: SessionEndStage {
        var name: String { "playEndSound" }

        func run(delegate: AppDelegate) {
            guard delegate.interactionSoundsEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                delegate.interactionSoundPlayer.playEnd()
            }
        }
    }

    private struct ResetSessionStateStage: SessionEndStage {
        var name: String { "resetSessionState" }

        func run(delegate: AppDelegate) {
            delegate.isSessionActive = false
            delegate.sessionOutputMode = .transcription
            delegate.isSelectedTextTranslationFlow = false
            delegate.sessionTargetApplicationPID = nil
            delegate.sessionTargetApplicationBundleID = nil
            delegate.enhancementContextSnapshot = nil
            delegate.rewriteSessionHasSelectedSourceText = false
            delegate.rewriteSessionHadWritableFocusedInput = false
            delegate.rewriteSessionFallbackInjectBundleID = nil
            delegate.resetSessionTranslationState()
            delegate.overlayState.isCompleting = false
            if delegate.overlayState.displayMode != .answer {
                delegate.overlayState.reset()
            }
            delegate.pendingSessionFinishTask = nil
        }
    }

    @MainActor
    func executeSessionEndPipeline() {
        VoxtLog.info("Session end pipeline started. displayMode=\(overlayState.displayMode), overlayVisible=\(overlayWindow.isVisible)")
        let stages: [any SessionEndStage] = [
            HideOverlayStage(),
            RestoreSystemAudioStage(),
            PlayEndSoundStage(),
            ResetSessionStateStage()
        ]
        for stage in stages {
            stage.run(delegate: self)
        }
        VoxtLog.info("Session end pipeline completed. overlayVisible=\(overlayWindow.isVisible)")
    }
}
