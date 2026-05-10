import Foundation

struct SanitizedRemoteProviderConfiguration: Codable {
    var providerID: String
    var model: String
    var meetingModel: String
    var endpoint: String
    var apiKey: String
    var appID: String
    var accessToken: String
    var searchEnabled: Bool
    var openAIChunkPseudoRealtimeEnabled: Bool
    var doubaoDictionaryMode: String
    var doubaoEnableRequestHotwords: Bool
    var doubaoEnableRequestCorrections: Bool
    var ollamaResponseFormat: String
    var ollamaJSONSchema: String
    var ollamaThinkMode: String
    var ollamaKeepAlive: String
    var ollamaLogprobsEnabled: Bool
    var ollamaTopLogprobs: Int?
    var ollamaOptionsJSON: String

    enum CodingKeys: String, CodingKey {
        case providerID
        case model
        case meetingModel
        case endpoint
        case apiKey
        case appID
        case accessToken
        case searchEnabled
        case openAIChunkPseudoRealtimeEnabled
        case doubaoDictionaryMode
        case doubaoEnableRequestHotwords
        case doubaoEnableRequestCorrections
        case ollamaResponseFormat
        case ollamaJSONSchema
        case ollamaThinkMode
        case ollamaKeepAlive
        case ollamaLogprobsEnabled
        case ollamaTopLogprobs
        case ollamaOptionsJSON
    }

    init(
        providerID: String,
        model: String,
        meetingModel: String,
        endpoint: String,
        apiKey: String,
        appID: String,
        accessToken: String,
        searchEnabled: Bool,
        openAIChunkPseudoRealtimeEnabled: Bool,
        doubaoDictionaryMode: String,
        doubaoEnableRequestHotwords: Bool,
        doubaoEnableRequestCorrections: Bool,
        ollamaResponseFormat: String,
        ollamaJSONSchema: String,
        ollamaThinkMode: String,
        ollamaKeepAlive: String,
        ollamaLogprobsEnabled: Bool,
        ollamaTopLogprobs: Int?,
        ollamaOptionsJSON: String
    ) {
        self.providerID = providerID
        self.model = model
        self.meetingModel = meetingModel
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
        self.searchEnabled = searchEnabled
        self.openAIChunkPseudoRealtimeEnabled = openAIChunkPseudoRealtimeEnabled
        self.doubaoDictionaryMode = doubaoDictionaryMode
        self.doubaoEnableRequestHotwords = doubaoEnableRequestHotwords
        self.doubaoEnableRequestCorrections = doubaoEnableRequestCorrections
        self.ollamaResponseFormat = ollamaResponseFormat
        self.ollamaJSONSchema = ollamaJSONSchema
        self.ollamaThinkMode = ollamaThinkMode
        self.ollamaKeepAlive = ollamaKeepAlive
        self.ollamaLogprobsEnabled = ollamaLogprobsEnabled
        self.ollamaTopLogprobs = ollamaTopLogprobs
        self.ollamaOptionsJSON = ollamaOptionsJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        meetingModel = try container.decodeIfPresent(String.self, forKey: .meetingModel) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        let defaultSearchEnabled = RemoteLLMProvider(rawValue: providerID)?.defaultSearchEnabled ?? false
        searchEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchEnabled) ?? defaultSearchEnabled
        openAIChunkPseudoRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIChunkPseudoRealtimeEnabled) ?? false
        doubaoDictionaryMode = try container.decodeIfPresent(String.self, forKey: .doubaoDictionaryMode) ?? DoubaoDictionaryMode.requestScoped.rawValue
        doubaoEnableRequestHotwords = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestHotwords) ?? true
        doubaoEnableRequestCorrections = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestCorrections) ?? true
        ollamaResponseFormat = try container.decodeIfPresent(String.self, forKey: .ollamaResponseFormat) ?? OllamaResponseFormat.plain.rawValue
        ollamaJSONSchema = try container.decodeIfPresent(String.self, forKey: .ollamaJSONSchema) ?? ""
        ollamaThinkMode = try container.decodeIfPresent(String.self, forKey: .ollamaThinkMode) ?? OllamaThinkMode.off.rawValue
        ollamaKeepAlive = try container.decodeIfPresent(String.self, forKey: .ollamaKeepAlive) ?? ""
        ollamaLogprobsEnabled = try container.decodeIfPresent(Bool.self, forKey: .ollamaLogprobsEnabled) ?? false
        ollamaTopLogprobs = try container.decodeIfPresent(Int.self, forKey: .ollamaTopLogprobs)
        ollamaOptionsJSON = try container.decodeIfPresent(String.self, forKey: .ollamaOptionsJSON) ?? ""
    }
}

extension ConfigurationTransferManager {
    static func sanitizeRemoteConfigurations(_ raw: String) -> [SanitizedRemoteProviderConfiguration] {
        let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return stored.values.sorted(by: { $0.providerID < $1.providerID }).map {
            SanitizedRemoteProviderConfiguration(
                providerID: $0.providerID,
                model: $0.model,
                meetingModel: $0.meetingModel,
                endpoint: $0.endpoint,
                apiKey: sanitizeSensitive($0.apiKey),
                appID: sanitizeSensitive($0.appID),
                accessToken: sanitizeSensitive($0.accessToken),
                searchEnabled: $0.searchEnabled,
                openAIChunkPseudoRealtimeEnabled: $0.openAIChunkPseudoRealtimeEnabled,
                doubaoDictionaryMode: $0.doubaoDictionaryMode,
                doubaoEnableRequestHotwords: $0.doubaoEnableRequestHotwords,
                doubaoEnableRequestCorrections: $0.doubaoEnableRequestCorrections,
                ollamaResponseFormat: $0.ollamaResponseFormat,
                ollamaJSONSchema: $0.ollamaJSONSchema,
                ollamaThinkMode: $0.ollamaThinkMode,
                ollamaKeepAlive: $0.ollamaKeepAlive,
                ollamaLogprobsEnabled: $0.ollamaLogprobsEnabled,
                ollamaTopLogprobs: $0.ollamaTopLogprobs,
                ollamaOptionsJSON: $0.ollamaOptionsJSON
            )
        }
    }

    static func restoreRemoteConfigurations(_ values: [SanitizedRemoteProviderConfiguration]) -> String {
        let mapped = Dictionary(uniqueKeysWithValues: values.map { item in
            (
                item.providerID,
                RemoteProviderConfiguration(
                    providerID: item.providerID,
                    model: item.model,
                    meetingModel: item.meetingModel,
                    endpoint: item.endpoint,
                    apiKey: resolveImportedSensitive(item.apiKey),
                    appID: resolveImportedSensitive(item.appID),
                    accessToken: resolveImportedSensitive(item.accessToken),
                    searchEnabled: item.searchEnabled,
                    openAIChunkPseudoRealtimeEnabled: item.openAIChunkPseudoRealtimeEnabled,
                    doubaoDictionaryMode: item.doubaoDictionaryMode,
                    doubaoEnableRequestHotwords: item.doubaoEnableRequestHotwords,
                    doubaoEnableRequestCorrections: item.doubaoEnableRequestCorrections,
                    ollamaResponseFormat: item.ollamaResponseFormat,
                    ollamaJSONSchema: item.ollamaJSONSchema,
                    ollamaThinkMode: item.ollamaThinkMode,
                    ollamaKeepAlive: item.ollamaKeepAlive,
                    ollamaLogprobsEnabled: item.ollamaLogprobsEnabled,
                    ollamaTopLogprobs: item.ollamaTopLogprobs,
                    ollamaOptionsJSON: item.ollamaOptionsJSON
                )
            )
        })
        return RemoteModelConfigurationStore.saveConfigurations(mapped)
    }
}
