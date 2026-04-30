import XCTest
@testable import Voxt

final class CustomLLMModelSupportTests: XCTestCase {
    func testCatalogRecognizesSupportedRepoAndFallbackTitle() {
        XCTAssertTrue(CustomLLMModelCatalog.isSupportedModelRepo("mlx-community/Qwen3-4B-4bit"))
        XCTAssertFalse(CustomLLMModelCatalog.isSupportedModelRepo("unsupported/repo"))
        XCTAssertEqual(
            CustomLLMModelCatalog.displayTitle(for: "mlx-community/Qwen3-4B-4bit"),
            "Qwen3 4B (4bit)"
        )
        XCTAssertEqual(
            CustomLLMModelCatalog.displayTitle(for: "custom/repo"),
            "custom/repo"
        )
    }

    func testCatalogProvidesFallbackRemoteSizeTextForCuratedRepos() {
        let missingRepos = CustomLLMModelCatalog.availableModels
            .map(\.id)
            .filter { CustomLLMModelCatalog.fallbackRemoteSizeText(repo: $0) == nil }
        XCTAssertTrue(missingRepos.isEmpty, "Missing size fallbacks for repos: \(missingRepos)")
    }

    func testStorageSupportBuildsExpectedCacheDirectory() {
        let rootDirectory = URL(fileURLWithPath: "/tmp/voxt-tests", isDirectory: true)
        let directory = CustomLLMModelStorageSupport.cacheDirectory(
            for: "mlx-community/Qwen3-4B-4bit",
            rootDirectory: rootDirectory
        )
        XCTAssertEqual(
            directory?.path,
            "/tmp/voxt-tests/mlx-llm/mlx-community_Qwen3-4B-4bit"
        )
    }
}
