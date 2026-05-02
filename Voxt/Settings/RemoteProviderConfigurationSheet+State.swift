import SwiftUI

extension RemoteProviderConfigurationSheet {
    var providerModelMenuOptions: [SettingsMenuOption<String>] {
        if let llmProvider = llmProviderForPicker {
            var options = (
                llmProvider.latestModelOptions +
                llmProvider.basicModelOptions +
                llmProvider.advancedModelOptions
            ).map { SettingsMenuOption(value: $0.id, title: $0.title) }
            if supportsCustomProviderModelSelection {
                options.append(SettingsMenuOption(value: customModelOptionID, title: AppLocalization.localizedString("Custom...")))
            }
            return options
        }
        var options = providerModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) }
        if supportsCustomProviderModelSelection {
            options.append(SettingsMenuOption(value: customModelOptionID, title: AppLocalization.localizedString("Custom...")))
        }
        return options
    }

    var providerModelSelectedTitle: String {
        providerModelMenuOptions.first(where: { $0.value == resolvedSelectionForPicker })?.title
            ?? AppLocalization.localizedString("Custom...")
    }

    var supportsCustomProviderModelSelection: Bool {
        RemoteProviderConfigurationPolicy.supportsCustomModelSelection(target: testTarget)
    }

    var shouldShowCustomProviderModelField: Bool {
        supportsCustomProviderModelSelection && resolvedSelectionForPicker == customModelOptionID
    }

    var customProviderModelPlaceholder: String {
        if isOpenAIASRTest {
            return AppLocalization.localizedString("e.g. gpt-4o-transcribe-xxx")
        }
        return AppLocalization.localizedString("e.g. doubao-seed-2-0-pro-260215")
    }

    var meetingModelMenuOptions: [SettingsMenuOption<String>] {
        meetingModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) } + [
            SettingsMenuOption(value: customModelOptionID, title: AppLocalization.localizedString("Custom..."))
        ]
    }

    var meetingModelSelectedTitle: String {
        meetingModelMenuOptions.first(where: { $0.value == resolvedMeetingSelectionForPicker })?.title
            ?? AppLocalization.localizedString("Custom...")
    }

    var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            meetingModel: resolvedMeetingModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            searchEnabled: (llmProviderForPicker?.supportsHostedSearch == true) ? searchEnabled : false,
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false,
            doubaoDictionaryMode: doubaoDictionaryMode,
            doubaoEnableRequestHotwords: doubaoEnableRequestHotwords,
            doubaoEnableRequestCorrections: doubaoEnableRequestCorrections
        )
    }

    var isDoubaoASRTest: Bool {
        RemoteProviderConfigurationPolicy.isDoubaoASRTest(testTarget)
    }

    var isOpenAIASRTest: Bool {
        RemoteProviderConfigurationPolicy.isOpenAIASRTest(testTarget)
    }

    var customModelOptionID: String {
        RemoteProviderConfigurationPolicy.customModelOptionID
    }

    var asrProviderForSheet: RemoteASRProvider? {
        if case .asr(let provider) = testTarget {
            return provider
        }
        if case .meetingASR(let provider) = testTarget {
            return provider
        }
        return nil
    }

    var activeProviderNotice: String? {
        switch testTarget {
        case .asr(let provider), .meetingASR(let provider):
            let active = RemoteASRProvider(rawValue: selectedRemoteASRProviderRaw) ?? .openAIWhisper
            guard active != provider else { return nil }
            return AppLocalization.format(
                "Current active Remote ASR provider is %@. Testing %@ here does not switch the active provider.",
                active.title,
                provider.title
            )
        case .llm(let provider):
            let active = RemoteLLMProvider(rawValue: selectedRemoteLLMProviderRaw) ?? .openAI
            guard active != provider else { return nil }
            return AppLocalization.format(
                "Current active Remote LLM provider is %@. Testing %@ here does not switch the active provider.",
                active.title,
                provider.title
            )
        }
    }

    var showsMeetingASRSection: Bool {
        guard let provider = asrProviderForSheet else { return false }
        return RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration)
    }

    var meetingModelOptions: [RemoteModelOption] {
        guard let provider = asrProviderForSheet else { return [] }
        return RemoteASRMeetingConfiguration.meetingModelOptions(for: provider)
    }

    var providerModelOptions: [RemoteModelOption] {
        RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    var resolvedSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedSelection(
            target: testTarget,
            selectedProviderModel: selectedProviderModel,
            configuredModel: configuration.model
        )
    }

    var providerModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedSelectionForPicker },
            set: {
                handleProviderModelSelectionChange($0)
            }
        )
    }

    var llmProviderForPicker: RemoteLLMProvider? {
        RemoteProviderConfigurationPolicy.llmProvider(for: testTarget)
    }

    var showsSearchSection: Bool {
        llmProviderForPicker?.supportsHostedSearch == true
    }

    func configureModelSelection() {
        selectedProviderModel = RemoteProviderConfigurationPolicy.initialSelection(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    func handleProviderModelSelectionChange(_ newValue: String) {
        let previousModel = resolvedModelValue()
        selectedProviderModel = newValue
        customModelID = RemoteProviderConfigurationPolicy.nextCustomModelID(
            previousResolvedModel: previousModel,
            newSelection: newValue,
            currentCustomModelID: customModelID,
            supportsCustomSelection: supportsCustomProviderModelSelection
        )

        endpoint = RemoteProviderConfigurationPolicy.remappedEndpointOnModelChange(
            target: testTarget,
            previousModel: previousModel,
            newModel: resolvedModelValue(),
            currentEndpoint: endpoint
        )
    }

    func configureMeetingModelSelection() {
        let trimmed = configuration.meetingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionIDs = Set(meetingModelOptions.map(\.id))
        if optionIDs.contains(trimmed) {
            selectedMeetingModel = trimmed
            return
        }
        if let provider = asrProviderForSheet {
            let suggested = RemoteASRMeetingConfiguration.suggestedMeetingModel(for: provider)
            if optionIDs.contains(suggested) {
                selectedMeetingModel = suggested
                return
            }
        }
        selectedMeetingModel = customModelOptionID
    }

    func resolvedModelValue() -> String {
        RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: testTarget,
            resolvedSelection: resolvedSelectionForPicker,
            customModelID: customModelID
        )
    }

    var resolvedMeetingSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedMeetingSelection(
            selectedMeetingModel: selectedMeetingModel,
            configuredMeetingModel: configuration.meetingModel,
            meetingOptionIDs: meetingModelOptions.map(\.id)
        )
    }

    var meetingModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedMeetingSelectionForPicker },
            set: {
                handleMeetingModelSelectionChange($0)
            }
        )
    }

    func handleMeetingModelSelectionChange(_ newValue: String) {
        let previousModel = resolvedMeetingModelValue()
        selectedMeetingModel = newValue
        customMeetingModelID = RemoteProviderConfigurationPolicy.nextCustomModelID(
            previousResolvedModel: previousModel,
            newSelection: newValue,
            currentCustomModelID: customMeetingModelID,
            supportsCustomSelection: true
        )
    }

    func resolvedMeetingModelValue() -> String {
        guard showsMeetingASRSection else {
            return configuration.meetingModel
        }
        if resolvedMeetingSelectionForPicker == customModelOptionID {
            return customMeetingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return resolvedMeetingSelectionForPicker
    }

    var endpointPresets: [RemoteEndpointPreset] {
        RemoteProviderConfigurationPolicy.endpointPresets(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

    var endpointPresetHintText: String? {
        guard !endpointPresets.isEmpty else { return nil }
        guard let provider = llmProviderForPicker else { return nil }

        switch provider {
        case .aliyunBailian:
            return AppLocalization.localizedString("Aliyun API keys are region-specific; use the matching endpoint.")
        case .volcengine:
            return AppLocalization.localizedString("Volcengine models should use the Responses endpoint in the same region as the API key.")
        default:
            return nil
        }
    }

    func testConnection() {
        runConnectionTest(for: testTarget, modelForLog: currentConfigurationSnapshot.model)
    }

    func testMeetingConnection() {
        guard let provider = asrProviderForSheet else { return }
        runConnectionTest(
            for: .meetingASR(provider),
            modelForLog: currentConfigurationSnapshot.meetingModel
        )
    }

    func runConnectionTest(
        for target: RemoteProviderTestTarget,
        modelForLog: String
    ) {
        let snapshot = currentConfigurationSnapshot
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        VoxtLog.info(
            "Remote provider test started. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), meetingModel=\(snapshot.meetingModel), endpoint=\(sanitizedEndpointForLog(snapshot.endpoint)), proxyMode=\(VoxtNetworkSession.modeDescription), hasAPIKey=\(!snapshot.apiKey.isEmpty), hasAppID=\(!snapshot.appID.isEmpty), hasAccessToken=\(!snapshot.accessToken.isEmpty)"
        )

        Task {
            do {
                let tester = RemoteProviderConnectivityTester(testTarget: target)
                let message = try await tester.run(configuration: snapshot)
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = true
                    testResultMessage = message
                    VoxtLog.info(
                        "Remote provider test succeeded. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), message=\(message)"
                    )
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = false
                    let message = VoxtNetworkSession.directModeConflictMessage(for: error) ?? error.localizedDescription
                    testResultMessage = message
                    VoxtLog.warning(
                        "Remote provider test failed. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), error=\(message)"
                    )
                }
            }
        }
    }

    func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }
}
