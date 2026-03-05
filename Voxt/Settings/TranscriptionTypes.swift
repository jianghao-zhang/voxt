import SwiftUI

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case dictation
    case mlxAudio

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dictation: return "Direct Dictation"
        case .mlxAudio: return "MLX Audio (On-device)"
        }
    }

    var title: String {
        switch self {
        case .dictation: return AppLocalization.localizedString("Direct Dictation")
        case .mlxAudio: return AppLocalization.localizedString("MLX Audio (On-device)")
        }
    }

    var description: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Uses Apple's built-in speech recognition. Works immediately with no setup.")
        case .mlxAudio:
            return AppLocalization.localizedString("Uses MLX Audio speech models running locally. Requires a one-time model download.")
        }
    }
}

enum EnhancementMode: String, CaseIterable, Identifiable {
    case off
    case appleIntelligence
    case customLLM

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        case .customLLM: return "Custom LLM"
        }
    }

    var title: String {
        switch self {
        case .off: return AppLocalization.localizedString("Off")
        case .appleIntelligence: return AppLocalization.localizedString("Apple Intelligence")
        case .customLLM: return AppLocalization.localizedString("Custom LLM")
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom
    case top

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        }
    }

    var title: String {
        switch self {
        case .bottom: return AppLocalization.localizedString("Bottom")
        case .top: return AppLocalization.localizedString("Top")
        }
    }
}
