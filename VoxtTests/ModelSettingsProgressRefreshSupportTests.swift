import XCTest
@testable import Voxt

final class ModelSettingsProgressRefreshSupportTests: XCTestCase {
    func testShouldRefreshCatalogForMetadataChangeOnlyWhenActiveAndVisible() {
        XCTAssertTrue(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: true,
                isWindowVisible: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: false,
                isWindowVisible: true
            )
        )
        XCTAssertFalse(
            ModelSettingsProgressRefreshSupport.shouldRefreshCatalogForMetadataChange(
                isActive: true,
                isWindowVisible: false
            )
        )
    }

    func testShouldPollModelStateWhenNonCurrentMLXDownloadIsActive() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .notDownloaded,
            mlxActiveDownloadRepos: [MLXModelManager.canonicalModelRepo("mlx-community/FireRedASR2-AED-mlx")],
            whisperState: .notDownloaded,
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded
        )

        XCTAssertTrue(shouldPoll)
    }

    func testShouldPollModelStateForActiveWhisperDownload() {
        let whisperDownload = WhisperKitModelManager.ActiveDownload(
            modelID: "openai_whisper-large-v3-v20240930",
            isPaused: false,
            progress: 0.5,
            completed: 50,
            total: 100,
            currentFile: "weights.bin",
            currentFileCompleted: 25,
            currentFileTotal: 50,
            completedFiles: 1,
            totalFiles: 2
        )

        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .notDownloaded,
            mlxActiveDownloadRepos: [],
            whisperState: .notDownloaded,
            whisperActiveDownload: whisperDownload,
            customLLMState: .notDownloaded
        )

        XCTAssertTrue(shouldPoll)
    }

    func testShouldNotPollModelStateWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .downloaded,
            mlxActiveDownloadRepos: [],
            whisperState: .downloaded,
            whisperActiveDownload: nil,
            customLLMState: .downloaded
        )

        XCTAssertFalse(shouldPoll)
    }

    func testShouldNotPollModelStateForLoadingWithoutActiveDownloads() {
        let shouldPoll = ModelSettingsProgressRefreshSupport.shouldPollModelState(
            mlxState: .loading,
            mlxActiveDownloadRepos: [],
            whisperState: .loading,
            whisperActiveDownload: nil,
            customLLMState: .notDownloaded
        )

        XCTAssertFalse(shouldPoll)
    }
}
