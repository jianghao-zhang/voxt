import Foundation

enum ModelDownloadProgressFormatter {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func progressText(completed: Int64, total: Int64) -> String {
        let completedText = byteFormatter.string(fromByteCount: completed)
        if total > 0 {
            return AppLocalization.format(
                "Downloaded: %@ / %@",
                completedText,
                byteFormatter.string(fromByteCount: total)
            )
        }
        return AppLocalization.format("Downloaded: %@", completedText)
    }

    static func fileProgressText(currentFile: String?, completedFiles: Int, totalFiles: Int) -> String {
        let filesText: String
        if totalFiles > 0 {
            filesText = AppLocalization.format("%d/%d files", completedFiles, totalFiles)
        } else {
            filesText = AppLocalization.format("%d files", completedFiles)
        }

        guard let currentFile, !currentFile.isEmpty else {
            return AppLocalization.format("Preparing download... (%@)", filesText)
        }

        let fileName = (currentFile as NSString).lastPathComponent
        return AppLocalization.format("Downloading: %@ (%@)", fileName, filesText)
    }
}
