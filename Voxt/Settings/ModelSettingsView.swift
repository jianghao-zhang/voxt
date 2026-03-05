import SwiftUI
import AppKit
import Combine

struct ModelSettingsView: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.translationSystemPrompt) private var translationPrompt = AppPreferenceKey.defaultTranslationPrompt
    @AppStorage(AppPreferenceKey.mlxModelRepo) private var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.customLLMModelRepo) private var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) private var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.useHfMirror) private var useHfMirror = false
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    @State private var showMirrorInfo = false
    private let modelStateRefreshTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .mlxAudio
    }

    private var selectedEnhancementMode: EnhancementMode {
        EnhancementMode(rawValue: enhancementModeRaw) ?? .off
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Engine")
                        .font(.headline)

                    Picker("Engine", selection: $engineRaw) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Text(engine.titleKey).tag(engine.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)

                    Text(selectedEngine.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if selectedEngine == .mlxAudio {
                        mlxModelSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Enhancement")
                        .font(.headline)

                    Picker("Enhancement", selection: $enhancementModeRaw) {
                        Text(EnhancementMode.off.titleKey).tag(EnhancementMode.off.rawValue)
                        Text(EnhancementMode.appleIntelligence.titleKey).tag(EnhancementMode.appleIntelligence.rawValue)
                        Text(EnhancementMode.customLLM.titleKey).tag(EnhancementMode.customLLM.rawValue)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    if selectedEnhancementMode == .appleIntelligence {
                        appleIntelligenceSection
                    }

                    if selectedEnhancementMode == .customLLM {
                        customLLMSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Translation")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Custom LLM Model")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Translation Custom LLM Model", selection: $translationCustomLLMRepo) {
                            ForEach(CustomLLMModelManager.availableModels) { model in
                                Text(model.title).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 280, alignment: .trailing)
                    }

                    Text("Translation Prompt")
                        .font(.subheadline.weight(.medium))
                    PromptEditorView(text: $translationPrompt)

                    HStack {
                        Text("Use {target_language} placeholder in the prompt for selected target language.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to Default") {
                            translationPrompt = AppPreferenceKey.defaultTranslationPrompt
                        }
                        .controlSize(.small)
                        .disabled(translationPrompt == AppPreferenceKey.defaultTranslationPrompt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            TranscriptionTestSectionView()
        }
        .onAppear {
            let canonicalRepo = MLXModelManager.canonicalModelRepo(modelRepo)
            if canonicalRepo != modelRepo {
                modelRepo = canonicalRepo
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
            mlxModelManager.prefetchAllModelSizes()

            if customLLMRepo.isEmpty {
                customLLMRepo = CustomLLMModelManager.defaultModelRepo
            }
            if !CustomLLMModelManager.isSupportedModelRepo(customLLMRepo) {
                customLLMRepo = CustomLLMModelManager.defaultModelRepo
            }
            if translationCustomLLMRepo.isEmpty {
                translationCustomLLMRepo = customLLMRepo
            }
            if !CustomLLMModelManager.isSupportedModelRepo(translationCustomLLMRepo) {
                translationCustomLLMRepo = customLLMRepo
            }
            if translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translationPrompt = AppPreferenceKey.defaultTranslationPrompt
            }
            customLLMManager.updateModel(repo: customLLMRepo)
            customLLMManager.prefetchAllModelSizes()
            updateMirrorSetting()
            refreshModelInstallStateIfNeeded()
        }
        .onChange(of: modelRepo) { _, newValue in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
            if canonicalRepo != newValue {
                modelRepo = canonicalRepo
                return
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
        }
        .onChange(of: customLLMRepo) { _, newValue in
            customLLMManager.updateModel(repo: newValue)
            if translationCustomLLMRepo.isEmpty {
                translationCustomLLMRepo = newValue
            }
        }
        .onChange(of: useHfMirror) { _, _ in
            updateMirrorSetting()
        }
        .onReceive(modelStateRefreshTimer) { _ in
            refreshModelInstallStateIfNeeded()
        }
        .id(interfaceLanguageRaw)
    }

    @ViewBuilder
    private var mlxModelSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                Picker("Model", selection: $modelRepo) {
                    ForEach(MLXModelManager.availableModels) { model in
                        Text(model.title).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                Spacer()

                HStack(spacing: 6) {
                    Toggle("Use China mirror", isOn: $useHfMirror)
                        .toggleStyle(.switch)

                    Button {
                        showMirrorInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showMirrorInfo, arrowEdge: .top) {
                        Text("https://hf-mirror.com/")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
            }

            Text(modelLocalizedDescription(for: modelRepo))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        mlxModelTable

        if case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = mlxModelManager.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Downloading: %d%% • %@", comment: ""),
                        Int(progress * 100),
                        ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(
                    ModelDownloadProgressFormatter.fileProgressText(
                        currentFile: currentFile,
                        completedFiles: completedFiles,
                        totalFiles: totalFiles
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var appleIntelligenceSection: some View {
        Divider()

        if appleIntelligenceAvailable {
            Text("System Prompt")
                .font(.subheadline.weight(.medium))

            PromptEditorView(text: $systemPrompt)

            HStack {
                Text("Customise how Apple Intelligence enhances your transcriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Default") {
                    systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
                }
                .controlSize(.small)
                .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
            }
        } else {
            Text("Apple Intelligence is not available on this Mac, so system prompt enhancement cannot be used.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var customLLMSection: some View {
        Divider()

        Text("System Prompt")
            .font(.subheadline.weight(.medium))

        PromptEditorView(text: $systemPrompt)

        customLLMModelTable

        if case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = customLLMManager.state {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Custom LLM downloading: %d%% • %@", comment: ""),
                        Int(progress * 100),
                        ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(
                    ModelDownloadProgressFormatter.fileProgressText(
                        currentFile: currentFile,
                        completedFiles: completedFiles,
                        totalFiles: totalFiles
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mlxModelTable: some View {
        ModelTableView(title: "Models", rows: mlxRows)
    }

    private var customLLMModelTable: some View {
        ModelTableView(title: "Custom LLM Models", rows: customLLMRows, maxHeight: 260)
    }

    private var mlxRows: [ModelTableRow] {
        MLXModelManager.availableModels.map { model in
            let isDownloaded = mlxModelManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingModel(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        mlxModelManager.cancelDownload()
                    }
                ]
            } else if mlxModelManager.isModelDownloaded(repo: model.id) {
                actions = [
                    ModelTableAction(
                        title: LocalizedStringKey(isCurrentModel(model.id) ? "Using" : "Use"),
                        isEnabled: !isCurrentModel(model.id)
                    ) {
                        useModel(model.id)
                    },
                    ModelTableAction(title: "Delete", role: .destructive) {
                        deleteModel(model.id)
                    }
                ]
            } else {
                actions = [
                    ModelTableAction(title: "Download", isEnabled: !isAnotherModelDownloading(model.id)) {
                        downloadModel(model.id)
                    }
                ]
            }

            return ModelTableRow(
                id: model.id,
                title: model.title,
                isActive: isCurrentModel(model.id),
                status: modelStatusText(for: model.id),
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openMLXModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    private var customLLMRows: [ModelTableRow] {
        CustomLLMModelManager.availableModels.map { model in
            let isDownloaded = customLLMManager.isModelDownloaded(repo: model.id)
            let actions: [ModelTableAction]
            if isDownloadingCustomLLM(model.id) {
                actions = [
                    ModelTableAction(title: "Cancel") {
                        customLLMManager.cancelDownload()
                    }
                ]
            } else if customLLMManager.isModelDownloaded(repo: model.id) {
                actions = [
                    ModelTableAction(
                        title: LocalizedStringKey(isCurrentCustomLLM(model.id) ? "Using" : "Use"),
                        isEnabled: !isCurrentCustomLLM(model.id)
                    ) {
                        useCustomLLM(model.id)
                    },
                    ModelTableAction(title: "Delete", role: .destructive) {
                        deleteCustomLLM(model.id)
                    }
                ]
            } else {
                actions = [
                    ModelTableAction(title: "Download", isEnabled: !isAnotherCustomLLMDownloading(model.id)) {
                        downloadCustomLLM(model.id)
                    }
                ]
            }

            return ModelTableRow(
                id: model.id,
                title: model.title,
                isActive: isCurrentCustomLLM(model.id),
                status: customLLMStatusText(for: model.id),
                isTitleUnderlined: isDownloaded,
                onTapTitle: isDownloaded ? { openCustomLLMModelDirectory(model.id) } : nil,
                actions: actions
            )
        }
    }

    private func useModel(_ repo: String) {
        let canonicalRepo = MLXModelManager.canonicalModelRepo(repo)
        modelRepo = canonicalRepo
        mlxModelManager.updateModel(repo: canonicalRepo)
    }

    private func downloadModel(_ repo: String) {
        Task {
            await mlxModelManager.downloadModel(repo: repo)
            modelRepo = MLXModelManager.canonicalModelRepo(repo)
        }
    }

    private func deleteModel(_ repo: String) {
        mlxModelManager.deleteModel(repo: repo)
        if MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo) {
            mlxModelManager.checkExistingModel()
        }
    }

    private func isCurrentModel(_ repo: String) -> Bool {
        MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(modelRepo)
    }

    private func isDownloadingModel(_ repo: String) -> Bool {
        guard isCurrentModel(repo) else { return false }
        if case .downloading = mlxModelManager.state {
            return true
        }
        return false
    }

    private func isAnotherModelDownloading(_ repo: String) -> Bool {
        guard case .downloading = mlxModelManager.state else { return false }
        return !isCurrentModel(repo)
    }

    private func modelStatusText(for repo: String) -> String {
        if isDownloadingModel(repo),
           case .downloading(_, let completed, let total, _, _, _) = mlxModelManager.state {
            return AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            )
        }

        if isCurrentModel(repo), case .error(let message) = mlxModelManager.state {
            return "Error: \(message)"
        }

        let installedSize = mlxModelManager.modelSizeOnDisk(repo: repo)
        if mlxModelManager.isModelDownloaded(repo: repo) {
            if installedSize.isEmpty {
                return AppLocalization.localizedString("Installed")
            }
            return AppLocalization.format("Installed (%@)", installedSize)
        }

        let remoteSize = mlxModelManager.remoteSizeText(repo: repo)
        return AppLocalization.format("Not installed (%@)", remoteSize)
    }

    private func useCustomLLM(_ repo: String) {
        customLLMRepo = repo
        customLLMManager.updateModel(repo: repo)
    }

    private func downloadCustomLLM(_ repo: String) {
        Task {
            await customLLMManager.downloadModel(repo: repo)
            customLLMRepo = repo
        }
    }

    private func deleteCustomLLM(_ repo: String) {
        customLLMManager.deleteModel(repo: repo)
        if repo == customLLMRepo {
            customLLMManager.checkExistingModel()
        }
    }

    private func isCurrentCustomLLM(_ repo: String) -> Bool {
        repo == customLLMRepo
    }

    private func isDownloadingCustomLLM(_ repo: String) -> Bool {
        guard isCurrentCustomLLM(repo) else { return false }
        if case .downloading = customLLMManager.state {
            return true
        }
        return false
    }

    private func isAnotherCustomLLMDownloading(_ repo: String) -> Bool {
        guard case .downloading = customLLMManager.state else { return false }
        return !isCurrentCustomLLM(repo)
    }

    private func customLLMStatusText(for repo: String) -> String {
        if isDownloadingCustomLLM(repo),
           case .downloading(_, let completed, let total, _, _, _) = customLLMManager.state {
            return AppLocalization.format(
                "Downloading %@",
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            )
        }

        if isCurrentCustomLLM(repo), case .error(let message) = customLLMManager.state {
            return "Error: \(message)"
        }

        let installedSize = customLLMManager.modelSizeOnDisk(repo: repo)
        if customLLMManager.isModelDownloaded(repo: repo) {
            if installedSize.isEmpty {
                return AppLocalization.localizedString("Installed")
            }
            return AppLocalization.format("Installed (%@)", installedSize)
        }

        let remoteSize = customLLMManager.remoteSizeText(repo: repo)
        return AppLocalization.format("Not installed (%@)", remoteSize)
    }

    private func updateMirrorSetting() {
        let url = useHfMirror ? MLXModelManager.mirrorHubBaseURL : MLXModelManager.defaultHubBaseURL
        mlxModelManager.updateHubBaseURL(url)
        customLLMManager.updateHubBaseURL(url)
    }

    private func refreshModelInstallStateIfNeeded() {
        if case .downloading = mlxModelManager.state {
            // Keep current transient state during active downloads.
        } else if case .loading = mlxModelManager.state {
            // Avoid resetting while model is being loaded.
        } else {
            mlxModelManager.checkExistingModel()
        }

        if case .downloading = customLLMManager.state {
            // Keep current transient state during active downloads.
        } else {
            customLLMManager.checkExistingModel()
        }
    }

    private func openMLXModelDirectory(_ repo: String) {
        guard let folderURL = mlxModelManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    private func openCustomLLMModelDirectory(_ repo: String) {
        guard let folderURL = customLLMManager.modelDirectoryURL(repo: repo) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    private func modelLocalizedDescription(for repo: String) -> LocalizedStringKey {
        switch MLXModelManager.canonicalModelRepo(repo) {
        case "mlx-community/Qwen3-ASR-0.6B-4bit":
            return "Balanced quality and speed with low memory use."
        case "mlx-community/Qwen3-ASR-1.7B-bf16":
            return "High accuracy flagship model with higher memory usage."
        case "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16":
            return "Realtime-oriented model with larger memory footprint."
        case "mlx-community/parakeet-tdt-0.6b-v3":
            return "Fast, lightweight English STT."
        case "mlx-community/GLM-ASR-Nano-2512-4bit":
            return "Smallest footprint for quick drafts."
        default:
            if let model = MLXModelManager.availableModels.first(where: { $0.id == repo }) {
                return LocalizedStringKey(model.description)
            }
            return LocalizedStringKey("")
        }
    }
}
