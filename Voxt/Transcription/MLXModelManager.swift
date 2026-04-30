import Foundation
import Combine
import CFNetwork
import MLX
import MLXAudioSTT
import HuggingFace

@MainActor
class MLXModelManager: ObservableObject {
    static let defaultHubBaseURL = URL(string: "https://huggingface.co")!
    static let mirrorHubBaseURL = URL(string: "https://hf-mirror.com")!
    static let hubUserAgent = "Voxt/1.0 (MLXAudio)"
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(
            progress: Double,
            completed: Int64,
            total: Int64,
            currentFile: String?,
            completedFiles: Int,
            totalFiles: Int
        )
        case downloaded
        case loading
        case ready
        case error(String)
    }

    typealias ModelOption = MLXModelCatalog.Option

    nonisolated static let defaultModelRepo = MLXModelCatalog.defaultModelRepo
    nonisolated static let availableModels = MLXModelCatalog.availableModels

    enum ModelSizeState: Equatable {
        case unknown
        case loading
        case ready(bytes: Int64, text: String)
        case error(String)
    }

    struct TranscriptionBehavior: Equatable {
        enum CorrectionMode: Equatable {
            case incremental
            case finalizationOnly
        }

        let correctionMode: CorrectionMode
        let allowsQuickStopPass: Bool
        let preloadsOnRecordingStart: Bool

        var runsIntermediateCorrections: Bool {
            correctionMode == .incremental
        }
    }

    @Published private(set) var state: ModelState = .notDownloaded
    @Published private(set) var sizeState: ModelSizeState = .unknown
    @Published private(set) var remoteSizeTextByRepo: [String: String] = [:]

    private var downloadedStateByRepo: [String: Bool] = [:]
    private var localSizeTextByRepo: [String: String] = [:]
    private var modelRepo: String
    private var hubBaseURL: URL
    private var loadedModel: (any STTGenerationModel)?
    private var loadedRepo: String?
    private var loadingTask: Task<Void, Error>?
    private var loadingRepo: String?
    private var downloadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var downloadTempDir: URL?
    private let downloadSizeTolerance: Double = 0.9
    private let downloadRetryLimit = 3
    private let idleUnloadDelay: Duration = .seconds(90)
    private var activeUseCount = 0

    init(modelRepo: String, hubBaseURL: URL = URL(string: "https://huggingface.co")!) {
        self.modelRepo = Self.canonicalModelRepo(modelRepo)
        self.hubBaseURL = hubBaseURL
        self.remoteSizeTextByRepo = MLXModelStorageSupport.loadPersistedRemoteSizeCache()
        checkExistingModel()
    }

    var currentModelRepo: String { modelRepo }
    var isCurrentModelLoaded: Bool { loadedModel != nil && loadedRepo == modelRepo }

    func displayTitle(for repo: String) -> String {
        MLXModelCatalog.displayTitle(for: repo)
    }

    nonisolated static func fallbackRemoteSizeText(repo: String) -> String? {
        MLXModelCatalog.fallbackRemoteSizeText(repo: repo)
    }

    func isModelDownloaded(repo: String) -> Bool {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let cached = downloadedStateByRepo[canonicalRepo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: canonicalRepo) else { return false }
        let isDownloaded = MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default)
        downloadedStateByRepo[canonicalRepo] = isDownloaded
        return isDownloaded
    }

    func modelSizeOnDisk(repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let cached = localSizeTextByRepo[canonicalRepo] {
            return cached
        }
        guard let modelDir = cacheDirectory(for: canonicalRepo),
              let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelDir),
              size > 0
        else {
            return ""
        }
        let text = MLXModelStorageSupport.formatByteCount(Int64(size))
        localSizeTextByRepo[canonicalRepo] = text
        return text
    }

    func modelDirectoryURL(repo: String) -> URL? {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard let modelDir = cacheDirectory(for: canonicalRepo),
              FileManager.default.fileExists(atPath: modelDir.path)
        else { return nil }
        return modelDir
    }

    func deleteModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if canonicalRepo == modelRepo {
            deleteModel()
            return
        }

        if let repoID = Repo.ID(rawValue: canonicalRepo) {
            MLXModelStorageSupport.clearHubCache(for: repoID)
        }
        if let modelDir = cacheDirectory(for: canonicalRepo) {
            try? FileManager.default.removeItem(at: modelDir)
        }
        invalidateLocalCache(for: canonicalRepo)
    }

    func downloadModel(repo: String) async {
        updateModel(repo: repo)
        await downloadModel()
    }

    func updateModel(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard canonicalRepo != modelRepo else { return }
        cancelIdleUnloadTask()
        loadingTask?.cancel()
        loadingTask = nil
        loadingRepo = nil
        modelRepo = canonicalRepo
        loadedModel = nil
        loadedRepo = nil
        activeUseCount = 0
        Memory.clearCache()
        checkExistingModel()
        fetchRemoteSize()
    }

    nonisolated static func canonicalModelRepo(_ repo: String) -> String {
        MLXModelCatalog.canonicalModelRepo(repo)
    }

    nonisolated static func isRealtimeCapableModelRepo(_ repo: String) -> Bool {
        MLXModelCatalog.isRealtimeCapableModelRepo(repo)
    }

    nonisolated static func transcriptionBehavior(for repo: String) -> TranscriptionBehavior {
        let canonicalRepo = canonicalModelRepo(repo)
        if canonicalRepo.localizedCaseInsensitiveContains("firered") {
            return TranscriptionBehavior(
                correctionMode: .finalizationOnly,
                allowsQuickStopPass: false,
                preloadsOnRecordingStart: true
            )
        }

        return TranscriptionBehavior(
            correctionMode: .incremental,
            allowsQuickStopPass: true,
            preloadsOnRecordingStart: true
        )
    }

    var currentTranscriptionBehavior: TranscriptionBehavior {
        Self.transcriptionBehavior(for: modelRepo)
    }

    func updateHubBaseURL(_ url: URL) {
        guard url != hubBaseURL else { return }
        hubBaseURL = url
        fetchRemoteSize()
    }

    func checkExistingModel() {
        guard let modelDir = cacheDirectory(for: modelRepo) else {
            state = .error("Invalid model identifier")
            downloadedStateByRepo[modelRepo] = false
            return
        }

        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            state = .notDownloaded
            downloadedStateByRepo[modelRepo] = false
            return
        }

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            downloadedStateByRepo[modelRepo] = true
            if loadedModel != nil, loadedRepo == modelRepo {
                state = .ready
            } else {
                state = .downloaded
            }
        } else {
            state = .notDownloaded
            downloadedStateByRepo[modelRepo] = false
        }
    }

    func downloadModel() async {
        if downloadTask != nil { return }
        if case .loading = state { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { downloadTask = nil }
            setDownloadingState(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
            do {
                let modelDir = try await performDownloadWithFallback()
                try Task.checkCancellation()
                try MLXModelDownloadSupport.validateDownloadedModel(
                    at: modelDir,
                    sizeState: sizeState,
                    downloadSizeTolerance: downloadSizeTolerance,
                    fileManager: .default
                )
                checkExistingModel()
                VoxtLog.info("Download complete.")
            } catch is CancellationError {
                cleanupPartialDownload()
                state = .notDownloaded
            } catch {
                clearCurrentRepoHubCache()
                state = .error(downloadErrorMessage(for: error))
                VoxtLog.error("Download error: \(error.localizedDescription)")
            }
        }
    }

    func cancelDownload() {
        guard downloadTask != nil else { return }
        downloadTask?.cancel()
        downloadTask = nil
        cleanupPartialDownload()
        clearCurrentRepoHubCache()
        state = .notDownloaded
    }

    func loadModel() async throws -> any STTGenerationModel {
        cancelIdleUnloadTask()
        if let model = loadedModel, loadedRepo == modelRepo {
            VoxtLog.info("MLX Audio model reuse existing instance. repo=\(modelRepo)", verbose: true)
            return model
        }
        if let loadingTask, loadingRepo == modelRepo {
            VoxtLog.info("MLX Audio model awaiting in-flight load. repo=\(modelRepo)", verbose: true)
            try await loadingTask.value
            return try readyModel(for: modelRepo)
        }

        let repo = modelRepo
        let startedAt = Date()
        VoxtLog.info("MLX Audio model load started. repo=\(repo)", verbose: true)
        state = .loading
        let loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let model = try await Self.loadSTTModel(for: repo)
            guard !Task.isCancelled else { return }
            guard self.loadingRepo == repo else { return }
            self.loadedModel = model
            self.loadedRepo = repo
            self.state = .ready
        }
        self.loadingTask = loadingTask
        self.loadingRepo = repo
        do {
            try await loadingTask.value
            self.loadingTask = nil
            self.loadingRepo = nil
            let model = try readyModel(for: repo)
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.info("MLX Audio model load completed. repo=\(repo), elapsedMs=\(elapsedMs)")
            return model
        } catch {
            self.loadingTask = nil
            self.loadingRepo = nil
            state = .error("Model load failed: \(error.localizedDescription)")
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            VoxtLog.error("MLX Audio model load failed. repo=\(repo), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)")
            throw error
        }
    }

    func deleteModel() {
        cancelIdleUnloadTask()
        loadingTask?.cancel()
        loadingTask = nil
        loadingRepo = nil
        loadedModel = nil
        loadedRepo = nil
        activeUseCount = 0
        Memory.clearCache()

        clearCurrentRepoHubCache()

        guard let modelDir = cacheDirectory(for: modelRepo) else {
            state = .notDownloaded
            invalidateLocalCache(for: modelRepo)
            return
        }
        try? FileManager.default.removeItem(at: modelDir)
        invalidateLocalCache(for: modelRepo)
        state = .notDownloaded
    }

    func beginActiveUse() {
        activeUseCount += 1
        cancelIdleUnloadTask()
    }

    func endActiveUse() {
        activeUseCount = max(0, activeUseCount - 1)
        guard activeUseCount == 0 else { return }
        scheduleIdleUnloadIfNeeded()
    }

    var modelSizeOnDisk: String {
        modelSizeOnDisk(repo: modelRepo)
    }

    private func invalidateLocalCache(for repo: String) {
        downloadedStateByRepo.removeValue(forKey: repo)
        localSizeTextByRepo.removeValue(forKey: repo)
    }

    private func readyModel(for repo: String) throws -> any STTGenerationModel {
        guard let model = loadedModel, loadedRepo == repo else {
            throw NSError(
                domain: "Voxt.MLXModelManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model load finished without a ready model instance."]
            )
        }
        return model
    }

    private static func loadSTTModel(for repo: String) async throws -> any STTGenerationModel {
        let lower = repo.lowercased()
        if lower.contains("forcedaligner") {
            throw NSError(
                domain: "MLXModelManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Qwen3-ForcedAligner is alignment-only and not supported by Voxt transcription."]
            )
        }
        if lower.contains("glmasr") || lower.contains("glm-asr") {
            return try await GLMASRModel.fromPretrained(repo)
        }
        if lower.contains("firered") {
            return try await FireRedASR2Model.fromPretrained(repo)
        }
        if lower.contains("sensevoice") {
            return try await SenseVoiceModel.fromPretrained(repo)
        }
        if lower.contains("qwen3-asr") || lower.contains("qwen3_asr") {
            return try await Qwen3ASRModel.fromPretrained(repo)
        }
        if lower.contains("voxtral") {
            return try await VoxtralRealtimeModel.fromPretrained(repo)
        }
        if lower.contains("cohere") {
            return try await CohereTranscribeModel.fromPretrained(repo)
        }
        if lower.contains("parakeet") {
            return try await ParakeetModel.fromPretrained(repo)
        }
        if lower.contains("granite") {
            return try await GraniteSpeechModel.fromPretrained(repo)
        }

        return try await Qwen3ASRModel.fromPretrained(repo)
    }

    private func cacheDirectory(for repo: String) -> URL? {
        MLXModelStorageSupport.cacheDirectory(
            for: repo,
            rootDirectory: ModelStorageDirectoryManager.resolvedRootURL()
        )
    }

    private func cleanupPartialDownload() {
        if let tempDir = downloadTempDir {
            try? FileManager.default.removeItem(at: tempDir)
            downloadTempDir = nil
        }
        guard let modelDir = cacheDirectory(for: modelRepo) else { return }
        try? FileManager.default.removeItem(at: modelDir)
    }

    private func fetchRemoteSize() {
        sizeTask?.cancel()
        sizeState = .loading
        let repo = modelRepo

        sizeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sizeInfo = try await loadRemoteSizeInfo(repo: repo)
                if Task.isCancelled { return }
                sizeState = .ready(bytes: sizeInfo.bytes, text: sizeInfo.text)
                updateRemoteSizeCache(repo: repo, text: sizeInfo.text)
            } catch is CancellationError {
                return
            } catch {
                if let fallback = MLXModelCatalog.fallbackRemoteSizeInfo(repo: repo) {
                    sizeState = .ready(bytes: fallback.bytes, text: fallback.text)
                    updateRemoteSizeCache(repo: repo, text: fallback.text)
                } else {
                    sizeState = .error("Size unavailable")
                    updateRemoteSizeCache(repo: repo, text: "Unknown")
                }
            }
        }
    }

    func remoteSizeText(repo: String) -> String {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        if let cached = remoteSizeTextByRepo[canonicalRepo] {
            return cached
        }
        if canonicalRepo == modelRepo {
            switch sizeState {
            case .unknown:
                return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
            case .loading:
                return "Loading…"
            case .ready(_, let text):
                return text
            case .error:
                return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
            }
        }
        return Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
    }

    func ensureRemoteSizeLoaded(repo: String) {
        let canonicalRepo = Self.canonicalModelRepo(repo)
        guard remoteSizeTextByRepo[canonicalRepo] == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await loadRemoteSizeInfo(repo: canonicalRepo)
                await MainActor.run {
                    self.updateRemoteSizeCache(repo: canonicalRepo, text: info.text)
                }
            } catch {
                await MainActor.run {
                    self.updateRemoteSizeCache(
                        repo: canonicalRepo,
                        text: Self.fallbackRemoteSizeText(repo: canonicalRepo) ?? "Unknown"
                    )
                }
            }
        }
    }

    func prefetchAllModelSizes() {
        guard prefetchTask == nil else { return }
        let repos = Self.availableModels
            .map { Self.canonicalModelRepo($0.id) }
            .filter { remoteSizeTextByRepo[$0] == nil }
        guard !repos.isEmpty else { return }

        let baseURL = hubBaseURL
        prefetchTask = Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.prefetchTask = nil
                }
            }
            for repo in repos {
                guard let self else { return }
                do {
                    let info = try await self.loadRemoteSizeInfo(repo: repo, preferredBaseURL: baseURL)
                    await MainActor.run {
                        self.updateRemoteSizeCache(repo: repo, text: info.text)
                    }
                } catch {
                    await MainActor.run {
                        self.updateRemoteSizeCache(
                            repo: repo,
                            text: Self.fallbackRemoteSizeText(repo: repo) ?? "Unknown"
                        )
                    }
                }
            }
        }
    }

    private func updateRemoteSizeCache(repo: String, text: String) {
        remoteSizeTextByRepo[repo] = text
        MLXModelStorageSupport.savePersistedRemoteSizeCache(remoteSizeTextByRepo)
    }

    private func fallbackHubBaseURL(from baseURL: URL) -> URL? {
        guard !MLXModelDownloadSupport.isMirrorHost(baseURL) else { return nil }
        return Self.mirrorHubBaseURL
    }

    private func loadRemoteSizeInfo(
        repo: String,
        preferredBaseURL: URL? = nil
    ) async throws -> (bytes: Int64, text: String) {
        let baseURL = preferredBaseURL ?? hubBaseURL
        do {
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: baseURL,
                userAgent: Self.hubUserAgent,
                formatByteCount: MLXModelStorageSupport.formatByteCount
            )
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: baseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary model metadata endpoint failed. Retrying with mirror. repo=\(repo), baseURL=\(baseURL.absoluteString), error=\(error.localizedDescription)"
            )
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: fallbackBaseURL,
                userAgent: Self.hubUserAgent,
                formatByteCount: MLXModelStorageSupport.formatByteCount
            )
        }
    }

    private func performDownloadWithFallback() async throws -> URL {
        do {
            return try await performDownload(using: hubBaseURL)
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(from: hubBaseURL) else {
                throw error
            }
            VoxtLog.warning(
                "Primary model download endpoint failed. Retrying with mirror. repo=\(modelRepo), baseURL=\(hubBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            cleanupPartialDownload()
            clearCurrentRepoHubCache()
            return try await performDownload(using: fallbackBaseURL)
        }
    }

    private func performDownload(using baseURL: URL) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: modelRepo) else {
            throw NSError(
                domain: "MLXModelManager",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model identifier"]
            )
        }
        let cache = HubCache.default
        let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "HF_TOKEN") as? String
        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        let client = MLXModelDownloadSupport.makeHubClient(
            session: session,
            baseURL: baseURL,
            cache: cache,
            token: token,
            userAgent: Self.hubUserAgent
        )
        VoxtLog.info("Model download transport: LFS-only (\(baseURL.absoluteString))")
        let resolvedCache = client.cache ?? cache
        return try await resolveOrDownloadModelUsingLFS(
            client: client,
            cache: resolvedCache,
            repoID: repoID,
            session: session,
            baseURL: baseURL
        )
    }

    private func resolveOrDownloadModelUsingLFS(
        client: HubClient,
        cache: HubCache,
        repoID: Repo.ID,
        session: URLSession,
        baseURL: URL
    ) async throws -> URL {
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let baseDir = ModelStorageDirectoryManager.resolvedRootURL().appendingPathComponent("mlx-audio")
        let modelDir = baseDir.appendingPathComponent(modelSubdir)
        let tempDir = baseDir.appendingPathComponent("\(modelSubdir)-download")

        if MLXModelDownloadSupport.isModelDirectoryValid(modelDir, fileManager: .default) {
            return modelDir
        }

        downloadTempDir = tempDir
        try MLXModelDownloadSupport.clearDirectory(at: tempDir, fileManager: .default)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        VoxtLog.info("Fetching model entries: \(repoID.description)")
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: Self.hubUserAgent
        )
        VoxtLog.info("Entry count: \(entries.count)")
        guard !entries.isEmpty else {
            throw MLXModelDownloadSupport.DownloadValidationError.emptyFileList
        }
        let totalBytes = max(entries.reduce(Int64(0)) { partial, entry in
            partial + max(entry.size ?? 0, 0)
        }, 1)
        let totalFiles = entries.count
        var completedBytes: Int64 = 0

        for (index, entry) in entries.enumerated() {
            let completedFiles = index
            let expectedEntryBytes = max(entry.size ?? 0, 0)
            let progress = Progress(totalUnitCount: max(expectedEntryBytes, 1))
            let baseCompletedBytes = completedBytes
            let beforeFraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
            setDownloadingState(
                progress: min(1, beforeFraction),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: entry.path,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )
            VoxtLog.info("Download start: \(entry.path) (size=\(entry.size ?? -1))", verbose: true)

            let sampler = Task { [weak self] in
                let startTime = Date()
                while !Task.isCancelled {
                    let effectiveInFlight = Self.inFlightBytes(
                        progress: progress,
                        expectedEntryBytes: expectedEntryBytes,
                        startTime: startTime
                    )
                    let currentCompleted = min(baseCompletedBytes + effectiveInFlight, totalBytes)
                    let fraction = totalBytes > 0 ? Double(currentCompleted) / Double(totalBytes) : 0
                    await MainActor.run {
                        self?.setDownloadingState(
                            progress: min(1, fraction),
                            completed: currentCompleted,
                            total: totalBytes,
                            currentFile: entry.path,
                            completedFiles: completedFiles,
                            totalFiles: totalFiles
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { sampler.cancel() }

            try await downloadEntryWithRetry(
                client: client,
                entryPath: entry.path,
                repoID: repoID,
                tempDir: tempDir,
                progress: progress
            )
            VoxtLog.info("Download done: \(entry.path)", verbose: true)
            let delta = max(expectedEntryBytes, max(progress.completedUnitCount, 0))
            completedBytes += max(delta, 0)
            let finishedFiles = completedFiles + 1
            let fraction = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 1
            setDownloadingState(
                progress: min(1, fraction),
                completed: min(completedBytes, totalBytes),
                total: totalBytes,
                currentFile: nil,
                completedFiles: finishedFiles,
                totalFiles: totalFiles
            )
            VoxtLog.info(
                "Download progress: files=\(finishedFiles)/\(totalFiles), bytes=\(min(completedBytes, totalBytes))/\(totalBytes)",
                verbose: true
            )
        }

        VoxtLog.info("Validating downloaded files...", verbose: true)
        try MLXModelDownloadSupport.validateDownloadedModel(
            at: tempDir,
            sizeState: sizeState,
            downloadSizeTolerance: downloadSizeTolerance,
            fileManager: .default
        )
        VoxtLog.info("Moving downloaded files into final cache...", verbose: true)
        try MLXModelDownloadSupport.clearDirectory(at: modelDir, fileManager: .default)
        try FileManager.default.moveItem(at: tempDir, to: modelDir)
        downloadTempDir = nil
        VoxtLog.info("Download files moved to final cache.", verbose: true)
        return modelDir
    }

    private func downloadEntryWithRetry(
        client: HubClient,
        entryPath: String,
        repoID: Repo.ID,
        tempDir: URL,
        progress: Progress
    ) async throws {
        let destination = try MLXModelStorageSupport.destinationFileURL(for: entryPath, under: tempDir)
        var attempt = 0
        while true {
            do {
                _ = try await client.downloadFile(
                    at: entryPath,
                    from: repoID,
                    to: destination,
                    kind: .model,
                    revision: "main",
                    progress: progress,
                    transport: .lfs,
                    localFilesOnly: false
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt <= downloadRetryLimit, isRetryableDownloadError(error) else {
                    throw error
                }
                let delayMs = Int(pow(2.0, Double(attempt - 1)) * 800.0)
                VoxtLog.warning("Download retry \(attempt)/\(downloadRetryLimit): \(entryPath) (\(error.localizedDescription))")
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
    }

    private func setDownloadingState(
        progress: Double,
        completed: Int64,
        total: Int64,
        currentFile: String?,
        completedFiles: Int,
        totalFiles: Int
    ) {
        let nextState = ModelState.downloading(
            progress: progress,
            completed: completed,
            total: total,
            currentFile: currentFile,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        )
        if state != nextState {
            state = nextState
        }
    }

    private static func inFlightBytes(
        progress: Progress,
        expectedEntryBytes: Int64,
        startTime: Date
    ) -> Int64 {
        let reported = max(progress.completedUnitCount, 0)
        guard reported == 0 else { return reported }

        let elapsed = Date().timeIntervalSince(startTime)
        let expectedForTenMinutes = Double(expectedEntryBytes) / (10 * 60)
        let fallbackRate = max(expectedForTenMinutes, 256 * 1024)
        let estimated = Int64(elapsed * fallbackRate)
        let cap = Int64(Double(expectedEntryBytes) * 0.95)
        return min(max(estimated, 0), max(cap, 0))
    }

    private func isRetryableDownloadError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled,
                 .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }

        if let httpError = error as? HTTPClientError {
            switch httpError {
            case .requestError, .unexpectedError:
                return true
            case .responseError(let response, _):
                return response.statusCode >= 500 || response.statusCode == 429 || response.statusCode == 408
            case .decodingError:
                return false
            }
        }

        return false
    }

    private func downloadErrorMessage(for error: Error) -> String {
        if let validationError = error as? MLXModelDownloadSupport.DownloadValidationError,
           let text = validationError.errorDescription
        {
            return text
        }

        if let networkError = error as? MLXModelDownloadSupport.DownloadNetworkError,
           let text = networkError.errorDescription
        {
            return text
        }

        if let httpError = error as? HTTPClientError {
            switch httpError {
            case .responseError(let response, let detail):
                if MLXModelDownloadSupport.isMirrorHost(hubBaseURL), [401, 403].contains(response.statusCode) {
                    return "China mirror rejected request (HTTP \(response.statusCode))."
                }
                if [401, 404].contains(response.statusCode) {
                    return "Model repository unavailable (\(modelRepo), HTTP \(response.statusCode))."
                }
                return "Download failed (HTTP \(response.statusCode)): \(detail)"
            case .decodingError(let response, _):
                return "Download failed while decoding server response (HTTP \(response.statusCode))."
            case .requestError(let detail):
                return "Download request failed: \(detail)"
            case .unexpectedError(let detail):
                return "Download failed: \(detail)"
            }
        }

        return "Download failed: \(error.localizedDescription)"
    }

    private func scheduleIdleUnloadIfNeeded() {
        guard loadedModel != nil else { return }
        idleUnloadTask?.cancel()
        let expectedRepo = loadedRepo
        let delay = idleUnloadDelay
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            await MainActor.run {
                self.unloadLoadedModelIfIdle(expectedRepo: expectedRepo)
            }
        }
    }

    private func cancelIdleUnloadTask() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func unloadLoadedModelIfIdle(expectedRepo: String?) {
        guard activeUseCount == 0 else { return }
        guard loadedModel != nil, loadedRepo == expectedRepo else { return }

        loadedModel = nil
        loadedRepo = nil
        idleUnloadTask = nil
        Memory.clearCache()
        checkExistingModel()
        VoxtLog.info("MLX Audio model released after idle period.", verbose: true)
    }

    private func clearCurrentRepoHubCache() {
        guard let repoID = Repo.ID(rawValue: modelRepo) else { return }
        MLXModelStorageSupport.clearHubCache(for: repoID)
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            totalSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        return totalSize
    }
}
