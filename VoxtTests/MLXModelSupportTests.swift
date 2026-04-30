import XCTest
@testable import Voxt

final class MLXModelSupportTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyRepos() {
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"),
            "mlx-community/Qwen3-ASR-0.6B-4bit"
        )
    }

    func testRealtimeCapabilityUsesCanonicalizedRepo() {
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602")
        )
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-6bit")
        )
        XCTAssertFalse(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit")
        )
    }

    func testFallbackRemoteSizeSupportsLegacyAndCuratedRepos() {
        XCTAssertEqual(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2"),
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2-AED-mlx")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3-ASR-0.6B-4bit")
        )
    }
}
