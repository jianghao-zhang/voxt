import SwiftUI

enum SettingsDisplayMode: Equatable {
    case normal
    case onboarding(step: OnboardingStep)
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case language
    case model
    case transcription
    case translation
    case rewrite
    case appEnhancement
    case meeting
    case finish

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .language:
            return "Language"
        case .model:
            return "Model"
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Rewrite"
        case .appEnhancement:
            return "App Enhancement"
        case .meeting:
            return "Meeting"
        case .finish:
            return "Finish"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .language:
            return "Choose interface language and main language."
        case .model:
            return "Choose one ASR model path and one LLM path for the rest of onboarding."
        case .transcription:
            return "Confirm microphone behavior, shortcut preset, and transcription basics."
        case .translation:
            return "Adjust output behavior and verify the current translation model path."
        case .rewrite:
            return "Understand voice rewrite mode for selected text and prompt-style generation."
        case .appEnhancement:
            return "Optionally enable app-aware prompt switching."
        case .meeting:
            return "Optionally enable the dedicated meeting workflow and verify blockers."
        case .finish:
            return "Import or export your setup, then leave onboarding."
        }
    }

    var title: String {
        AppLocalization.localizedString(rawTitleKey)
    }

    private var rawTitleKey: String {
        switch self {
        case .language:
            return "Language"
        case .model:
            return "Model"
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Rewrite"
        case .appEnhancement:
            return "App Enhancement"
        case .meeting:
            return "Meeting"
        case .finish:
            return "Finish"
        }
    }

    var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var previous: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }

    var next: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self),
              index + 1 < Self.allCases.count else {
            return nil
        }
        return Self.allCases[index + 1]
    }
}

enum OnboardingStepStatus: String {
    case ready
    case needsSetup
    case optional
    case done

    var titleKey: LocalizedStringKey {
        switch self {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs Setup"
        case .optional:
            return "Optional"
        case .done:
            return "Done"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .optional:
            return .secondary
        case .done:
            return .accentColor
        }
    }
}

struct OnboardingStepStatusSnapshot {
    var hasModelIssues: Bool
    var hasRecordingMicrophone: Bool
    var hasRecordingPermissions: Bool
    var hasRewriteIssues: Bool
    var appEnhancementEnabled: Bool
    var meetingNotesEnabled: Bool
    var hasMeetingIssues: Bool
}

enum OnboardingStepStatusResolver {
    static func resolve(
        step: OnboardingStep,
        snapshot: OnboardingStepStatusSnapshot
    ) -> OnboardingStepStatus {
        switch step {
        case .language:
            return .ready
        case .model:
            return snapshot.hasModelIssues ? .needsSetup : .ready
        case .transcription:
            return (snapshot.hasRecordingMicrophone && snapshot.hasRecordingPermissions) ? .ready : .needsSetup
        case .translation:
            return .ready
        case .rewrite:
            return snapshot.hasRewriteIssues ? .needsSetup : .ready
        case .appEnhancement:
            return snapshot.appEnhancementEnabled ? .ready : .optional
        case .meeting:
            guard snapshot.meetingNotesEnabled else { return .optional }
            return snapshot.hasMeetingIssues ? .needsSetup : .ready
        case .finish:
            return .done
        }
    }
}
