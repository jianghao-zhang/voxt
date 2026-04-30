import Foundation
import HuggingFace

enum CustomLLMModelDownloadSupport {
    struct DownloadContext {
        let repoID: Repo.ID
        let client: HubClient
        let entries: [MLXModelDownloadSupport.ModelFileEntry]
        let totalBytes: Int64
    }

    nonisolated static func fallbackHubBaseURL(
        from baseURL: URL,
        mirrorBaseURL: URL
    ) -> URL? {
        guard baseURL.host?.contains("hf-mirror.com") != true else { return nil }
        return mirrorBaseURL
    }

    nonisolated static func inFlightBytes(
        progress: Progress,
        expectedFileBytes: Int64,
        startTime: Date
    ) -> Int64 {
        let reported = max(progress.completedUnitCount, 0)
        guard reported == 0 else { return reported }

        let elapsed = Date().timeIntervalSince(startTime)
        let expectedForTenMinutes = Double(expectedFileBytes) / (10 * 60)
        let fallbackRate = max(expectedForTenMinutes, 256 * 1024)
        let estimated = Int64(elapsed * fallbackRate)
        let cap = Int64(Double(expectedFileBytes) * 0.95)
        return min(max(estimated, 0), max(cap, 0))
    }

    static func makeDownloadContext(
        repo: String,
        baseURL: URL,
        userAgent: String,
        token: String?,
        cache: HubCache = .default
    ) async throws -> DownloadContext {
        guard let repoID = Repo.ID(rawValue: repo) else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model identifier"]
            )
        }

        let session = MLXModelDownloadSupport.makeDownloadSession(for: baseURL)
        let client = MLXModelDownloadSupport.makeHubClient(
            session: session,
            baseURL: baseURL,
            cache: cache,
            token: token,
            userAgent: userAgent
        )
        let entries = try await MLXModelDownloadSupport.fetchModelEntries(
            repo: repoID.description,
            baseURL: baseURL,
            session: session,
            userAgent: userAgent
        )
        guard !entries.isEmpty else {
            throw NSError(
                domain: "Voxt.CustomLLM",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No downloadable files were found for this model."]
            )
        }

        let totalBytes = max(entries.reduce(Int64(0)) { $0 + max($1.size ?? 0, 0) }, 1)
        return DownloadContext(
            repoID: repoID,
            client: client,
            entries: entries,
            totalBytes: totalBytes
        )
    }

    static func fetchRemoteSizeInfo(
        repo: String,
        preferredBaseURL: URL,
        mirrorBaseURL: URL,
        userAgent: String,
        formatByteCount: @Sendable (Int64) -> String
    ) async throws -> (bytes: Int64, text: String) {
        do {
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: preferredBaseURL,
                userAgent: userAgent,
                formatByteCount: formatByteCount
            )
        } catch {
            guard let fallbackBaseURL = fallbackHubBaseURL(
                from: preferredBaseURL,
                mirrorBaseURL: mirrorBaseURL
            ) else {
                throw error
            }
            VoxtLog.warning(
                "Primary custom LLM metadata endpoint failed. Retrying with mirror. repo=\(repo), baseURL=\(preferredBaseURL.absoluteString), error=\(error.localizedDescription)"
            )
            return try await MLXModelDownloadSupport.fetchModelSizeInfo(
                repo: repo,
                baseURL: fallbackBaseURL,
                userAgent: userAgent,
                formatByteCount: formatByteCount
            )
        }
    }
}
