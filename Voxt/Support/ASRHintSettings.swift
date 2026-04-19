import Foundation

enum ASRHintTarget: String, CaseIterable, Codable, Identifiable {
    case dictation
    case mlxAudio
    case whisperKit
    case openAIWhisper
    case glmASR
    case doubaoASR
    case aliyunBailianASR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Direct Dictation")
        case .mlxAudio:
            return AppLocalization.localizedString("MLX Audio")
        case .whisperKit:
            return AppLocalization.localizedString("Whisper")
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI Whisper")
        case .glmASR:
            return AppLocalization.localizedString("GLM ASR")
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao ASR")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun Bailian ASR")
        }
    }

    var supportsPromptEditor: Bool {
        switch self {
        case .whisperKit, .openAIWhisper, .glmASR:
            return true
        case .dictation, .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return false
        }
    }

    var supportsLanguageHints: Bool {
        true
    }

    var defaultPromptTemplate: String {
        switch self {
        case .dictation:
            return ""
        case .whisperKit:
            return AppPreferenceKey.defaultWhisperASRHintPrompt
        case .openAIWhisper:
            return AppPreferenceKey.defaultOpenAIASRHintPrompt
        case .glmASR:
            return AppPreferenceKey.defaultGLMASRHintPrompt
        case .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return ""
        }
    }

    var helpText: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Direct Dictation uses your main language, optional contextual phrases, on-device preference, and punctuation settings. Prompt editing is not applied.")
        case .mlxAudio:
            return AppLocalization.localizedString("MLX uses language hints by default. Some model families also expose model-specific local tuning in the Configure dialog.")
        case .whisperKit:
            return AppLocalization.localizedString("Whisper uses the resolved main language and a short prompt bias. Keep the prompt concise and recognition-focused.")
        case .openAIWhisper:
            return AppLocalization.localizedString("OpenAI ASR uses the resolved main language and a short prompt bias. Keep the prompt concise and focused on recognition.")
        case .glmASR:
            return AppLocalization.localizedString("GLM ASR uses a short prompt bias. It does not use hotwords in Voxt.")
        case .doubaoASR:
            return AppLocalization.localizedString("Doubao ASR uses language hints. Chinese output follows your selected simplified or traditional main language automatically.")
        case .aliyunBailianASR:
            return AppLocalization.localizedString("Aliyun ASR uses language hints derived from your selected user languages.")
        }
    }

    var settingsTitle: String {
        switch self {
        case .dictation:
            return AppLocalization.localizedString("Dictation Settings")
        case .mlxAudio, .whisperKit, .openAIWhisper, .glmASR, .doubaoASR, .aliyunBailianASR:
            return AppLocalization.localizedString("Engine Hint Settings")
        }
    }

    static func from(engine: TranscriptionEngine, remoteProvider: RemoteASRProvider?) -> ASRHintTarget {
        switch engine {
        case .dictation:
            return .dictation
        case .mlxAudio:
            return .mlxAudio
        case .whisperKit:
            return .whisperKit
        case .remote:
            switch remoteProvider ?? .openAIWhisper {
            case .openAIWhisper:
                return .openAIWhisper
            case .glmASR:
                return .glmASR
            case .doubaoASR:
                return .doubaoASR
            case .aliyunBailianASR:
                return .aliyunBailianASR
            }
        }
    }
}

struct ASRHintSettings: Codable, Equatable {
    var followsUserMainLanguage: Bool = true
    var promptTemplate: String = ""
    var contextualPhrasesText: String = ""
    var prefersOnDeviceRecognition: Bool = false
    var addsPunctuation: Bool = true
    var reportsPartialResults: Bool = true

    init(
        followsUserMainLanguage: Bool = true,
        promptTemplate: String = "",
        contextualPhrasesText: String = "",
        prefersOnDeviceRecognition: Bool = false,
        addsPunctuation: Bool = true,
        reportsPartialResults: Bool = true
    ) {
        self.followsUserMainLanguage = followsUserMainLanguage
        self.promptTemplate = promptTemplate
        self.contextualPhrasesText = contextualPhrasesText
        self.prefersOnDeviceRecognition = prefersOnDeviceRecognition
        self.addsPunctuation = addsPunctuation
        self.reportsPartialResults = reportsPartialResults
    }

    enum CodingKeys: String, CodingKey {
        case followsUserMainLanguage
        case promptTemplate
        case contextualPhrasesText
        case prefersOnDeviceRecognition
        case addsPunctuation
        case reportsPartialResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        followsUserMainLanguage = try container.decodeIfPresent(Bool.self, forKey: .followsUserMainLanguage) ?? true
        promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate) ?? ""
        contextualPhrasesText = try container.decodeIfPresent(String.self, forKey: .contextualPhrasesText) ?? ""
        prefersOnDeviceRecognition = try container.decodeIfPresent(Bool.self, forKey: .prefersOnDeviceRecognition) ?? false
        addsPunctuation = try container.decodeIfPresent(Bool.self, forKey: .addsPunctuation) ?? true
        reportsPartialResults = try container.decodeIfPresent(Bool.self, forKey: .reportsPartialResults) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(followsUserMainLanguage, forKey: .followsUserMainLanguage)
        try container.encode(promptTemplate, forKey: .promptTemplate)
        try container.encode(contextualPhrasesText, forKey: .contextualPhrasesText)
        try container.encode(prefersOnDeviceRecognition, forKey: .prefersOnDeviceRecognition)
        try container.encode(addsPunctuation, forKey: .addsPunctuation)
        try container.encode(reportsPartialResults, forKey: .reportsPartialResults)
    }
}

enum ASRHintSettingsStore {
    static func load(from rawValue: String?) -> [ASRHintTarget: ASRHintSettings] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ASRHintSettings].self, from: data)
        else {
            return [:]
        }

        var result: [ASRHintTarget: ASRHintSettings] = [:]
        for (key, value) in decoded {
            guard let target = ASRHintTarget(rawValue: key) else { continue }
            result[target] = sanitized(value, for: target)
        }
        return result
    }

    static func resolvedSettings(for target: ASRHintTarget, rawValue: String?) -> ASRHintSettings {
        let stored = load(from: rawValue)
        return stored[target] ?? defaultSettings(for: target)
    }

    static func storageValue(for settingsByTarget: [ASRHintTarget: ASRHintSettings]) -> String {
        let serialized = Dictionary(uniqueKeysWithValues: settingsByTarget.map { key, value in
            (key.rawValue, sanitized(value, for: key))
        })
        guard let data = try? JSONEncoder().encode(serialized),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    static func defaultStoredValue() -> String {
        storageValue(for: Dictionary(uniqueKeysWithValues: ASRHintTarget.allCases.map { ($0, defaultSettings(for: $0)) }))
    }

    static func defaultSettings(for target: ASRHintTarget) -> ASRHintSettings {
        ASRHintSettings(
            followsUserMainLanguage: true,
            promptTemplate: target.defaultPromptTemplate
        )
    }

    static func sanitized(_ settings: ASRHintSettings, for target: ASRHintTarget) -> ASRHintSettings {
        let trimmedPrompt: String
        if target.supportsPromptEditor {
            let candidate = settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if target == .whisperKit,
               candidate == AppPreferenceKey.legacyDefaultWhisperASRHintPrompt.trimmingCharacters(in: .whitespacesAndNewlines) {
                trimmedPrompt = ""
            } else {
                trimmedPrompt = candidate
            }
        } else {
            trimmedPrompt = ""
        }

        let contextualPhrases = parseContextualPhrases(settings.contextualPhrasesText)

        return ASRHintSettings(
            followsUserMainLanguage: settings.followsUserMainLanguage,
            promptTemplate: trimmedPrompt,
            contextualPhrasesText: contextualPhrases.joined(separator: "\n"),
            prefersOnDeviceRecognition: settings.prefersOnDeviceRecognition,
            addsPunctuation: settings.addsPunctuation,
            reportsPartialResults: settings.reportsPartialResults
        )
    }

    static func contextualPhrases(from settings: ASRHintSettings) -> [String] {
        parseContextualPhrases(settings.contextualPhrasesText)
    }

    private static func parseContextualPhrases(_ rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ResolvedASRHintPayload {
    var language: String?
    var languageHints: [String] = []
    var chineseOutputVariant: String?
    var prompt: String?
    var otherLanguages: [String] = []
    var multilingualContext: String?
}

struct ResolvedDictationSettings: Equatable {
    var localeIdentifier: String?
    var contextualPhrases: [String]
    var prefersOnDeviceRecognition: Bool
    var addsPunctuation: Bool
    var reportsPartialResults: Bool
}

@MainActor
enum ASRHintResolver {
    static func resolve(
        target: ASRHintTarget,
        settings: ASRHintSettings,
        userLanguageCodes: [String],
        mlxModelRepo: String? = nil
    ) -> ResolvedASRHintPayload {
        let selectedOptions = selectedLanguageOptions(userLanguageCodes)
        let mainLanguage = selectedOptions.first ?? UserMainLanguageOption.fallbackOption()
        let otherLanguageOptions = Array(selectedOptions.dropFirst())
        let prompt = resolvePrompt(
            for: target,
            template: settings.promptTemplate,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguageOptions
        )
        let otherLanguages = otherLanguageOptions.map(\.promptName)
        let usesExplicitSingleLanguageHint = settings.followsUserMainLanguage && otherLanguageOptions.isEmpty
        let mlxResolvedLanguage = settings.followsUserMainLanguage
            ? resolvedMLXLanguageHint(
                mainLanguage: mainLanguage,
                otherLanguages: otherLanguageOptions,
                modelRepo: mlxModelRepo
            )
            : nil
        let multilingualContext = settings.followsUserMainLanguage
            ? resolvedMultilingualContext(mainLanguage: mainLanguage, otherLanguages: otherLanguageOptions)
            : nil

        switch target {
        case .dictation:
            return ResolvedASRHintPayload()
        case .mlxAudio:
            return ResolvedASRHintPayload(
                language: mlxResolvedLanguage,
                prompt: nil,
                otherLanguages: otherLanguages,
                multilingualContext: multilingualContext
            )
        case .whisperKit:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .openAIWhisper:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedOpenAILanguage(mainLanguage) : nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .glmASR:
            return ResolvedASRHintPayload(
                language: nil,
                prompt: prompt,
                otherLanguages: otherLanguages
            )
        case .doubaoASR:
            return ResolvedASRHintPayload(
                language: usesExplicitSingleLanguageHint ? resolvedDoubaoLanguage(mainLanguage) : nil,
                chineseOutputVariant: resolvedDoubaoChineseVariant(mainLanguage),
                prompt: nil,
                otherLanguages: otherLanguages
            )
        case .aliyunBailianASR:
            let hints = settings.followsUserMainLanguage ? resolvedAliyunLanguageHints(options: selectedOptions) : []
            return ResolvedASRHintPayload(
                language: hints.first,
                languageHints: hints,
                prompt: nil,
                otherLanguages: otherLanguages
            )
        }
    }

    static func selectedLanguageOptions(_ userLanguageCodes: [String]) -> [UserMainLanguageOption] {
        UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
    }

    static func selectedLanguageSummary(_ userLanguageCodes: [String]) -> String {
        selectedLanguageOptions(userLanguageCodes)
            .map(\.promptName)
            .joined(separator: ", ")
    }

    static func secondaryLanguageSummary(_ userLanguageCodes: [String]) -> String {
        let secondary = selectedLanguageOptions(userLanguageCodes)
            .dropFirst()
            .map(\.promptName)
        return secondary.isEmpty ? AppLocalization.localizedString("Not applied") : secondary.joined(separator: ", ")
    }

    static func outputVariantDescription(for mainLanguage: UserMainLanguageOption) -> String {
        guard mainLanguage.isChinese else {
            return AppLocalization.localizedString("Not applied")
        }
        return mainLanguage.isTraditionalChinese
            ? AppLocalization.localizedString("Traditional Chinese")
            : AppLocalization.localizedString("Simplified Chinese")
    }

    static func resolveDictationSettings(
        settings: ASRHintSettings,
        userLanguageCodes: [String]
    ) -> ResolvedDictationSettings {
        let mainLanguage = UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
            .first ?? UserMainLanguageOption.fallbackOption()

        return ResolvedDictationSettings(
            localeIdentifier: settings.followsUserMainLanguage ? resolvedDictationLocaleIdentifier(mainLanguage) : nil,
            contextualPhrases: ASRHintSettingsStore.contextualPhrases(from: settings),
            prefersOnDeviceRecognition: settings.prefersOnDeviceRecognition,
            addsPunctuation: settings.addsPunctuation,
            reportsPartialResults: settings.reportsPartialResults
        )
    }

    static func resolveTemplateVariables(
        in template: String,
        userLanguageCodes: [String],
        appendOtherLanguagesWhenMissing: Bool = false
    ) -> String {
        let selectedOptions = selectedLanguageOptions(userLanguageCodes)
        let mainLanguage = selectedOptions.first ?? UserMainLanguageOption.fallbackOption()
        let otherLanguages = Array(selectedOptions.dropFirst())
        return resolveTemplateVariables(
            in: template,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguages,
            appendOtherLanguagesWhenMissing: appendOtherLanguagesWhenMissing
        )
    }

    private static func resolvePrompt(
        for target: ASRHintTarget,
        template: String,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption]
    ) -> String? {
        guard target.supportsPromptEditor else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return autoGeneratedPrompt(
                for: target,
                mainLanguage: mainLanguage,
                otherLanguages: otherLanguages
            )
        }

        let resolved = resolveTemplateVariables(
            in: trimmed,
            mainLanguage: mainLanguage,
            otherLanguages: otherLanguages,
            appendOtherLanguagesWhenMissing: true
        )
        let compact = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    private static func resolveTemplateVariables(
        in template: String,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption],
        appendOtherLanguagesWhenMissing: Bool
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherLanguagesSummary = otherLanguages.isEmpty
            ? "None specified"
            : otherLanguages.map(\.promptName).joined(separator: ", ")

        var resolved = trimmed
            .replacingOccurrences(
                of: AppPreferenceKey.asrUserMainLanguageTemplateVariable,
                with: mainLanguage.promptName
            )
            .replacingOccurrences(
                of: AppPreferenceKey.asrUserOtherLanguagesTemplateVariable,
                with: otherLanguagesSummary
            )

        if appendOtherLanguagesWhenMissing,
           !otherLanguages.isEmpty,
           !trimmed.contains(AppPreferenceKey.asrUserOtherLanguagesTemplateVariable) {
            resolved += "\nOther frequently used languages: \(otherLanguagesSummary)."
        }

        return resolved
    }

    private static func autoGeneratedPrompt(
        for target: ASRHintTarget,
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption]
    ) -> String? {
        guard !otherLanguages.isEmpty else { return nil }
        let otherLanguagesSummary = otherLanguages.map(\.promptName).joined(separator: ", ")

        switch target {
        case .whisperKit, .openAIWhisper, .glmASR:
            return """
                The speaker's primary language is \(mainLanguage.promptName), and they may also speak \(otherLanguagesSummary). Mixed-language speech is expected. Preserve names, product terms, URLs, and code-like text exactly as spoken.
                """
        case .dictation, .mlxAudio, .doubaoASR, .aliyunBailianASR:
            return nil
        }
    }

    private static func resolvedMultilingualContext(
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption]
    ) -> String? {
        guard !otherLanguages.isEmpty else { return nil }
        let otherLanguagesSummary = otherLanguages.map(\.promptName).joined(separator: ", ")
        return """
            Primary language: \(mainLanguage.promptName)
            Other frequently used languages: \(otherLanguagesSummary)
            Mixed-language speech may appear. Preserve names, brands, URLs, and code-like text exactly as spoken.
            """
    }

    private static func resolvedOpenAILanguage(_ language: UserMainLanguageOption) -> String {
        language.baseLanguageCode
    }

    private static func resolvedDoubaoLanguage(_ language: UserMainLanguageOption) -> String? {
        switch language.baseLanguageCode {
        case "zh":
            return "zh-CN"
        case "en":
            return "en-US"
        case "ja":
            return "ja-JP"
        case "ko":
            return "ko-KR"
        case "id":
            return "id-ID"
        case "es":
            return "es-MX"
        default:
            return nil
        }
    }

    private static func resolvedDoubaoChineseVariant(_ language: UserMainLanguageOption) -> String? {
        guard language.isChinese else { return nil }
        return language.isTraditionalChinese ? "zh-Hant" : "zh-Hans"
    }

    private static func resolvedAliyunLanguageHints(options: [UserMainLanguageOption]) -> [String] {
        var seen = Set<String>()
        let mapped = options.compactMap { option -> String? in
            switch option.baseLanguageCode {
            case "zh":
                return "zh"
            case "en":
                return "en"
            case "ja":
                return "ja"
            case "ko":
                return "ko"
            default:
                return nil
            }
        }

        let deduped = mapped.filter { seen.insert($0).inserted }
        return Array(deduped.prefix(3))
    }

    private static func resolvedMLXLanguage(mainLanguage: UserMainLanguageOption, modelRepo: String?) -> String? {
        guard let modelRepo else { return nil }
        if modelRepo.localizedCaseInsensitiveContains("granite-4.0-1b-speech") {
            return nil
        }
        if modelRepo.localizedCaseInsensitiveContains("cohere-transcribe") || modelRepo.localizedCaseInsensitiveContains("cohere") {
            switch mainLanguage.baseLanguageCode {
            case "zh":
                return "zh"
            case "en":
                return "en"
            case "ja":
                return "ja"
            case "ko":
                return "ko"
            case "vi":
                return "vi"
            case "ar":
                return "ar"
            case "el":
                return "el"
            case "pl":
                return "pl"
            case "nl":
                return "nl"
            case "pt":
                return "pt"
            case "it":
                return "it"
            case "es":
                return "es"
            case "de":
                return "de"
            case "fr":
                return "fr"
            default:
                return nil
            }
        }
        if modelRepo.localizedCaseInsensitiveContains("Qwen3-ASR") {
            return mainLanguage.promptName
        }

        switch mainLanguage.baseLanguageCode {
        case "zh":
            return "zh"
        case "en":
            return "en"
        case "ja":
            return "ja"
        case "ko":
            return "ko"
        default:
            return mainLanguage.baseLanguageCode
        }
    }

    private static func resolvedMLXLanguageHint(
        mainLanguage: UserMainLanguageOption,
        otherLanguages: [UserMainLanguageOption],
        modelRepo: String?
    ) -> String? {
        guard let modelRepo else { return nil }

        if mlxRequiresExplicitPrimaryLanguage(modelRepo: modelRepo) {
            return resolvedMLXLanguage(mainLanguage: mainLanguage, modelRepo: modelRepo)
        }

        guard otherLanguages.isEmpty else { return nil }
        return resolvedMLXLanguage(mainLanguage: mainLanguage, modelRepo: modelRepo)
    }

    private static func mlxRequiresExplicitPrimaryLanguage(modelRepo: String) -> Bool {
        let lower = modelRepo.lowercased()
        return lower.contains("cohere-transcribe") || lower.contains("cohere")
    }

    private static func resolvedDictationLocaleIdentifier(_ mainLanguage: UserMainLanguageOption) -> String {
        switch mainLanguage.code {
        case "zh-hans":
            return "zh-CN"
        case "zh-hant":
            return "zh-TW"
        default:
            return mainLanguage.baseLanguageCode
        }
    }
}

enum LocalASRRecognitionPreset: String, CaseIterable, Codable, Identifiable {
    case balanced
    case accuracyFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return AppLocalization.localizedString("Balanced")
        case .accuracyFirst:
            return AppLocalization.localizedString("Accuracy First")
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return AppLocalization.localizedString("Default recognition behavior with moderate fallback and minimal extra bias.")
        case .accuracyFirst:
            return AppLocalization.localizedString("Stronger fallback and chunking choices that favor recognition stability over speed.")
        }
    }
}

enum MLXModelFamily: String, CaseIterable, Codable, Identifiable {
    case qwen3ASR
    case graniteSpeech
    case senseVoice
    case cohereTranscribe
    case generic

    var id: String { rawValue }

    static func family(for repo: String) -> MLXModelFamily {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        if canonicalRepo.localizedCaseInsensitiveContains("Qwen3-ASR") {
            return .qwen3ASR
        }
        if canonicalRepo.localizedCaseInsensitiveContains("granite-4.0-1b-speech") {
            return .graniteSpeech
        }
        if canonicalRepo.localizedCaseInsensitiveContains("sensevoice") {
            return .senseVoice
        }
        if canonicalRepo.localizedCaseInsensitiveContains("cohere-transcribe")
            || canonicalRepo.localizedCaseInsensitiveContains("cohere")
        {
            return .cohereTranscribe
        }
        return .generic
    }

    var title: String {
        switch self {
        case .qwen3ASR:
            return AppLocalization.localizedString("Qwen3-ASR")
        case .graniteSpeech:
            return AppLocalization.localizedString("Granite Speech")
        case .senseVoice:
            return AppLocalization.localizedString("SenseVoice")
        case .cohereTranscribe:
            return AppLocalization.localizedString("Cohere Transcribe")
        case .generic:
            return AppLocalization.localizedString("General MLX ASR")
        }
    }

    var supportsContextBias: Bool { self == .qwen3ASR }
    var supportsPromptBias: Bool { self == .graniteSpeech }
    var supportsITN: Bool { self == .senseVoice }
}

struct WhisperLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var temperatureFallbackCount: Int = 2
    var temperatureIncrementOnFallback: Double = 0.2
    var compressionRatioThreshold: Double = 2.4
    var logProbThreshold: Double = -1.0
    var noSpeechThreshold: Double = 0.6

    static func defaults(for preset: LocalASRRecognitionPreset) -> WhisperLocalTuningSettings {
        switch preset {
        case .balanced:
            return WhisperLocalTuningSettings(
                preset: .balanced,
                temperatureFallbackCount: 2,
                temperatureIncrementOnFallback: 0.2,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                noSpeechThreshold: 0.6
            )
        case .accuracyFirst:
            return WhisperLocalTuningSettings(
                preset: .accuracyFirst,
                temperatureFallbackCount: 4,
                temperatureIncrementOnFallback: 0.2,
                compressionRatioThreshold: 2.2,
                logProbThreshold: -1.2,
                noSpeechThreshold: 0.45
            )
        }
    }
}

enum WhisperLocalTuningSettingsStore {
    static func resolvedSettings(from rawValue: String?) -> WhisperLocalTuningSettings {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WhisperLocalTuningSettings.self, from: data)
        else {
            return WhisperLocalTuningSettings.defaults(for: .balanced)
        }
        return sanitized(decoded)
    }

    static func storageValue(for settings: WhisperLocalTuningSettings) -> String {
        let sanitized = sanitized(settings)
        guard let data = try? JSONEncoder().encode(sanitized),
              let text = String(data: data, encoding: .utf8) else {
            return defaultStoredValue()
        }
        return text
    }

    static func defaultStoredValue() -> String {
        storageValue(for: WhisperLocalTuningSettings.defaults(for: .balanced))
    }

    static func sanitized(_ settings: WhisperLocalTuningSettings) -> WhisperLocalTuningSettings {
        WhisperLocalTuningSettings(
            preset: settings.preset,
            temperatureFallbackCount: max(0, min(settings.temperatureFallbackCount, 8)),
            temperatureIncrementOnFallback: max(0, min(settings.temperatureIncrementOnFallback, 1.0)),
            compressionRatioThreshold: max(1.0, min(settings.compressionRatioThreshold, 4.0)),
            logProbThreshold: max(-3.0, min(settings.logProbThreshold, 0.0)),
            noSpeechThreshold: max(0.0, min(settings.noSpeechThreshold, 1.0))
        )
    }
}

struct MLXLocalTuningSettings: Codable, Equatable {
    var preset: LocalASRRecognitionPreset = .balanced
    var qwenContextBias: String = ""
    var granitePromptBias: String = ""
    var senseVoiceUseITN: Bool = false

    init(
        preset: LocalASRRecognitionPreset = .balanced,
        qwenContextBias: String = "",
        granitePromptBias: String = "",
        senseVoiceUseITN: Bool = false
    ) {
        self.preset = preset
        self.qwenContextBias = qwenContextBias
        self.granitePromptBias = granitePromptBias
        self.senseVoiceUseITN = senseVoiceUseITN
    }

    static func defaults(for preset: LocalASRRecognitionPreset) -> MLXLocalTuningSettings {
        MLXLocalTuningSettings(preset: preset)
    }
}

enum MLXLocalTuningSettingsStore {
    static func load(from rawValue: String?) -> [String: MLXLocalTuningSettings] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: MLXLocalTuningSettings].self, from: data)
        else {
            return [:]
        }

        var result: [String: MLXLocalTuningSettings] = [:]
        for (key, value) in decoded {
            result[key] = sanitized(value)
        }
        return result
    }

    static func resolvedSettings(for repo: String, rawValue: String?) -> MLXLocalTuningSettings {
        let key = familyKey(for: repo)
        return load(from: rawValue)[key] ?? MLXLocalTuningSettings.defaults(for: .balanced)
    }

    static func save(_ settings: MLXLocalTuningSettings, for repo: String, rawValue: String?) -> String {
        var stored = load(from: rawValue)
        stored[familyKey(for: repo)] = sanitized(settings)
        return storageValue(for: stored)
    }

    static func storageValue(for settingsByFamily: [String: MLXLocalTuningSettings]) -> String {
        let sanitizedSettings = settingsByFamily.mapValues { value in
            Self.sanitized(value)
        }
        guard let data = try? JSONEncoder().encode(sanitizedSettings),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func familyKey(for repo: String) -> String {
        MLXModelFamily.family(for: repo).rawValue
    }

    static func sanitized(_ settings: MLXLocalTuningSettings) -> MLXLocalTuningSettings {
        MLXLocalTuningSettings(
            preset: settings.preset,
            qwenContextBias: settings.qwenContextBias.trimmingCharacters(in: .whitespacesAndNewlines),
            granitePromptBias: settings.granitePromptBias.trimmingCharacters(in: .whitespacesAndNewlines),
            senseVoiceUseITN: settings.senseVoiceUseITN
        )
    }
}
