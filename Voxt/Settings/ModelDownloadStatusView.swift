import SwiftUI

struct ModelDownloadStatusSnapshot: Equatable {
    let progress: Double
    let titleText: String
    let detailText: String

    static func fromMLXState(_ state: MLXModelManager.ModelState) -> Self? {
        guard case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = state else {
            return nil
        }

        return .init(
            progress: progress,
            titleText: String(
                format: NSLocalizedString("Downloading: %d%% • %@", comment: ""),
                Int(progress * 100),
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            ),
            detailText: ModelDownloadProgressFormatter.fileProgressText(
                currentFile: currentFile,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )
        )
    }

    static func fromWhisperDownload(_ activeDownload: WhisperKitModelManager.ActiveDownload?) -> Self? {
        guard let activeDownload else { return nil }

        return .init(
            progress: activeDownload.progress,
            titleText: String(
                format: NSLocalizedString("Downloading: %d%% • %@", comment: ""),
                Int(activeDownload.progress * 100),
                ModelDownloadProgressFormatter.progressText(
                    completed: activeDownload.completed,
                    total: activeDownload.total
                )
            ),
            detailText: ModelDownloadProgressFormatter.fileProgressText(
                currentFile: activeDownload.currentFile,
                currentFileCompleted: activeDownload.currentFileCompleted,
                currentFileTotal: activeDownload.currentFileTotal,
                completedFiles: activeDownload.completedFiles,
                totalFiles: activeDownload.totalFiles
            )
        )
    }

    static func fromCustomLLMState(_ state: CustomLLMModelManager.ModelState) -> Self? {
        guard case .downloading(let progress, let completed, let total, let currentFile, let completedFiles, let totalFiles) = state else {
            return nil
        }

        return .init(
            progress: progress,
            titleText: String(
                format: NSLocalizedString("Custom LLM downloading: %d%% • %@", comment: ""),
                Int(progress * 100),
                ModelDownloadProgressFormatter.progressText(completed: completed, total: total)
            ),
            detailText: ModelDownloadProgressFormatter.fileProgressText(
                currentFile: currentFile,
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )
        )
    }
}

struct ModelDownloadStatusView: View {
    let status: ModelDownloadStatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: max(0, min(status.progress, 1)))
                .controlSize(.small)

            Text(status.titleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(status.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
