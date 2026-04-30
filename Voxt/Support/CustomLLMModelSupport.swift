import Foundation
import HuggingFace

struct CustomLLMModelBehavior: Equatable {
    let family: CustomLLMModelFamily
    let disablesThinking: Bool

    var additionalContext: [String: any Sendable]? {
        guard disablesThinking else { return nil }
        return ["enable_thinking": false]
    }
}

enum CustomLLMModelBehaviorResolver {
    static func behavior(for repo: String) -> CustomLLMModelBehavior {
        let family = CustomLLMModelFamily.resolve(for: repo)
        return CustomLLMModelBehavior(
            family: family,
            disablesThinking: family == .qwen3
        )
    }
}

enum CustomLLMTaskKind: Equatable {
    case enhancement
    case translation
    case rewrite

    var logLabel: String {
        switch self {
        case .enhancement: return "enhance"
        case .translation: return "translate"
        case .rewrite: return "rewrite"
        }
    }

    var tokenBudgetMultiplier: Double {
        switch self {
        case .enhancement:
            return 1.10
        case .translation, .rewrite:
            return 1.35
        }
    }
}

struct CustomLLMRepoSelection: Equatable {
    let requestedRepo: String
    let effectiveRepo: String

    var didFallback: Bool { requestedRepo != effectiveRepo }

    nonisolated static func resolve(
        requestedRepo: String,
        supportedRepos: [String],
        fallbackRepo: String
    ) -> CustomLLMRepoSelection {
        let effectiveRepo = isSupported(repo: requestedRepo, supportedRepos: supportedRepos)
            ? requestedRepo
            : fallbackRepo
        return CustomLLMRepoSelection(
            requestedRepo: requestedRepo,
            effectiveRepo: effectiveRepo
        )
    }

    nonisolated static func isSupported(repo: String, supportedRepos: [String]) -> Bool {
        supportedRepos.contains(repo)
    }
}

enum CustomLLMRemoteSizeCache {
    static let unknownText = "Unknown"

    static func cachedState(
        for repo: String,
        cache: [String: String]
    ) -> CustomLLMModelManager.ModelSizeState? {
        guard let cachedText = cache[repo], cachedText != unknownText else { return nil }
        return .ready(bytes: 0, text: cachedText)
    }

    static func shouldPrefetch(
        repo: String,
        cache: [String: String]
    ) -> Bool {
        cache[repo] == nil
    }

    static func updatedCache(
        _ cache: [String: String],
        repo: String,
        text: String
    ) -> [String: String] {
        var updated = cache
        updated[repo] = text
        return updated
    }
}

struct CustomLLMLogSection: Equatable {
    let label: String
    let content: String
}

struct CustomLLMRequestPlan: Equatable {
    let kind: CustomLLMTaskKind
    let repo: String
    let instructions: String
    let prompt: String
    let inputCharacterCount: Int
    let logMode: String?
    let contentLogSections: [CustomLLMLogSection]
    let resultFallback: String
    let responseExtractionMode: CustomLLMResponseExtractionMode
}

enum CustomLLMResponseExtractionMode: Equatable {
    case textResultPayloadOrNormalizedText
    case normalizedRawText
}

enum CustomLLMRequestPlanBuilder {
    static func enhancement(
        input: String,
        systemPrompt: String,
        repo: String,
        resultFallback: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Clean up this transcription while preserving meaning and style.",
            input
        )
        return CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: systemPrompt,
            prompt: prompt,
            inputCharacterCount: input.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: systemPrompt),
                CustomLLMLogSection(label: "input", content: input),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: resultFallback,
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func userPromptEnhancement(
        prompt: String,
        repo: String
    ) -> CustomLLMRequestPlan {
        CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: "",
            prompt: prompt,
            inputCharacterCount: prompt.count,
            logMode: "userMessage",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func translation(
        text: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let prompt = structuredOutputPrompt(
            "Process the input according to the instructions.",
            text
        )
        return CustomLLMRequestPlan(
            kind: .translation,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: text.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: text),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        instructions: String,
        repo: String,
        structuredOutputPrompt: (String, String) -> String
    ) -> CustomLLMRequestPlan {
        let combinedInput = """
        Spoken instruction:
        \(dictatedPrompt)

        Selected source text:
        \(sourceText)
        """
        let prompt = structuredOutputPrompt(
            "Produce the final text to insert according to the instructions.",
            combinedInput
        )
        return CustomLLMRequestPlan(
            kind: .rewrite,
            repo: repo,
            instructions: instructions,
            prompt: prompt,
            inputCharacterCount: combinedInput.count,
            logMode: nil,
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: instructions),
                CustomLLMLogSection(label: "input", content: combinedInput),
                CustomLLMLogSection(label: "request_content", content: prompt)
            ],
            resultFallback: "",
            responseExtractionMode: .textResultPayloadOrNormalizedText
        )
    }

    static func dictionaryHistoryScan(
        prompt: String,
        repo: String,
        structuredOutputPrompt: (String) -> String
    ) -> CustomLLMRequestPlan {
        let requestPrompt = structuredOutputPrompt(prompt)
        return CustomLLMRequestPlan(
            kind: .enhancement,
            repo: repo,
            instructions: "",
            prompt: requestPrompt,
            inputCharacterCount: prompt.count,
            logMode: "dictionaryHistoryScan",
            contentLogSections: [
                CustomLLMLogSection(label: "system_prompt", content: "<empty>"),
                CustomLLMLogSection(label: "input", content: prompt),
                CustomLLMLogSection(label: "request_content", content: requestPrompt)
            ],
            resultFallback: "[]",
            responseExtractionMode: .normalizedRawText
        )
    }
}

enum CustomLLMModelFamily: Equatable {
    case qwen2
    case qwen3
    case glm4
    case llama
    case mistral
    case gemma
    case other

    var logLabel: String {
        switch self {
        case .qwen2: return "qwen2"
        case .qwen3: return "qwen3"
        case .glm4: return "glm4"
        case .llama: return "llama"
        case .mistral: return "mistral"
        case .gemma: return "gemma"
        case .other: return "other"
        }
    }

    static func resolve(for repo: String) -> CustomLLMModelFamily {
        let normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRepo.contains("qwen3") { return .qwen3 }
        if normalizedRepo.contains("qwen2") { return .qwen2 }
        if normalizedRepo.contains("glm-4") || normalizedRepo.contains("glm4") { return .glm4 }
        if normalizedRepo.contains("llama") { return .llama }
        if normalizedRepo.contains("mistral") { return .mistral }
        if normalizedRepo.contains("gemma") { return .gemma }
        return .other
    }
}

enum CustomLLMOutputSanitizer {
    static func normalizeResultText(_ output: String) -> String {
        var cleaned = output
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        cleaned = unwrapCodeFenceIfNeeded(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unwrapCodeFenceIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

struct CustomLLMModelCatalog {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let description: String
    }

    nonisolated static let defaultModelRepo = "Qwen/Qwen2-1.5B-Instruct"

    nonisolated static let availableModels: [Option] = [
        Option(
            id: "Qwen/Qwen2-1.5B-Instruct",
            title: "Qwen2 1.5B Instruct",
            description: "General-purpose instruction model for prompt-based text cleanup."
        ),
        Option(
            id: "Qwen/Qwen2.5-3B-Instruct",
            title: "Qwen2.5 3B Instruct",
            description: "Larger instruction model with stronger reasoning and formatting quality."
        ),
        Option(
            id: "mlx-community/Qwen3-4B-4bit",
            title: "Qwen3 4B (4bit)",
            description: "Balanced Qwen3 model for quality and performance."
        ),
        Option(
            id: "mlx-community/Qwen3-8B-4bit",
            title: "Qwen3 8B (4bit)",
            description: "Higher-quality Qwen3 model for stronger enhancement results."
        ),
        Option(
            id: "mlx-community/GLM-4-9B-0414-4bit",
            title: "GLM-4 9B (4bit)",
            description: "GLM-4 model variant with strong multilingual instruction following."
        ),
        Option(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            title: "Llama 3.2 3B Instruct (4bit)",
            description: "Lightweight Llama 3.2 model for fast local enhancement."
        ),
        Option(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            title: "Llama 3.2 1B Instruct (4bit)",
            description: "Smallest Llama 3.2 option with minimal memory footprint."
        ),
        Option(
            id: "mlx-community/Meta-Llama-3-8B-Instruct-4bit",
            title: "Meta Llama 3 8B Instruct (4bit)",
            description: "General-purpose 8B instruction model with strong quality."
        ),
        Option(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            title: "Meta Llama 3.1 8B Instruct (4bit)",
            description: "Refined 8B Llama 3.1 instruction model."
        ),
        Option(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            title: "Mistral 7B Instruct v0.3 (4bit)",
            description: "Reliable 7B instruction model for concise formatting tasks."
        ),
        Option(
            id: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            title: "Mistral Nemo Instruct 2407 (4bit)",
            description: "Nemo-based Mistral model with improved instruction quality."
        ),
        Option(
            id: "mlx-community/gemma-2-2b-it-4bit",
            title: "Gemma 2 2B IT (4bit)",
            description: "Compact Gemma 2 instruction-tuned model."
        ),
        Option(
            id: "mlx-community/gemma-2-9b-it-4bit",
            title: "Gemma 2 9B IT (4bit)",
            description: "Higher-capacity Gemma 2 model for better quality output."
        )
    ]

    nonisolated private static let knownRemoteSizeBytesByRepo: [String: Int64] = [
        "Qwen/Qwen2-1.5B-Instruct": 3_098_962_420,
        "Qwen/Qwen2.5-3B-Instruct": 6_183_464_935,
        "mlx-community/Qwen3-4B-4bit": 2_278_972_183,
        "mlx-community/Qwen3-8B-4bit": 4_623_784_971,
        "mlx-community/GLM-4-9B-0414-4bit": 5_309_031_270,
        "mlx-community/Llama-3.2-3B-Instruct-4bit": 1_824_825_759,
        "mlx-community/Llama-3.2-1B-Instruct-4bit": 712_593_855,
        "mlx-community/Meta-Llama-3-8B-Instruct-4bit": 5_281_878_323,
        "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit": 4_526_698_444,
        "mlx-community/Mistral-7B-Instruct-v0.3-4bit": 4_080_222_853,
        "mlx-community/Mistral-Nemo-Instruct-2407-4bit": 6_905_203_123,
        "mlx-community/gemma-2-2b-it-4bit": 1_492_852_888,
        "mlx-community/gemma-2-9b-it-4bit": 5_217_089_310,
    ]

    nonisolated static func displayTitle(for repo: String) -> String {
        availableModels.first(where: { $0.id == repo })?.title ?? repo
    }

    nonisolated static func isSupportedModelRepo(_ repo: String) -> Bool {
        CustomLLMRepoSelection.isSupported(repo: repo, supportedRepos: availableModels.map(\.id))
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        fallbackRemoteSizeInfo(repo: repo)?.text
    }

    nonisolated static func fallbackRemoteSizeInfo(repo: String) -> (bytes: Int64, text: String)? {
        guard let bytes = knownRemoteSizeBytesByRepo[repo] else { return nil }
        return (bytes, CustomLLMModelStorageSupport.formatByteCount(bytes))
    }
}

enum CustomLLMModelStorageSupport {
    nonisolated private static let remoteSizeCachePreferenceKey = "customLLMRemoteSizeCache"

    nonisolated static func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    nonisolated static func loadPersistedRemoteSizeCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: remoteSizeCachePreferenceKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated static func savePersistedRemoteSizeCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: remoteSizeCachePreferenceKey)
    }

    nonisolated static func destinationFileURL(for entryPath: String, under directory: URL) throws -> URL {
        let base = directory.standardizedFileURL
        let destination = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePrefix = base.path.hasSuffix("/") ? base.path : "\(base.path)/"
        guard destination.path.hasPrefix(basePrefix) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model file path: \(entryPath)"]
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
    }

    nonisolated static func cacheDirectory(for repo: String, rootDirectory: URL) -> URL? {
        guard let repoID = Repo.ID(rawValue: repo) else { return nil }
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        return rootDirectory
            .appendingPathComponent("mlx-llm")
            .appendingPathComponent(modelSubdir)
    }

    nonisolated static func isModelDirectoryValid(_ directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        let rootConfig = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: rootConfig.path),
              let rootConfigData = try? Data(contentsOf: rootConfig),
              (try? JSONSerialization.jsonObject(with: rootConfigData)) != nil
        else {
            return false
        }

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "safetensors" {
            return true
        }
        return false
    }

    nonisolated static func clearHubCache(for repoID: Repo.ID) {
        let cache = HubCache.default
        let repoDir = cache.repoDirectory(repo: repoID, kind: .model)
        let metadataDir = cache.metadataDirectory(repo: repoID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metadataDir)
    }
}
