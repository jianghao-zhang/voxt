import XCTest
@testable import Voxt

final class CustomLLMModelDownloadSupportTests: XCTestCase {
    func testFallbackHubBaseURLUsesMirrorOnlyForPrimaryHost() {
        let primaryURL = URL(string: "https://huggingface.co")!
        let mirrorURL = URL(string: "https://hf-mirror.com")!

        XCTAssertEqual(
            CustomLLMModelDownloadSupport.fallbackHubBaseURL(
                from: primaryURL,
                mirrorBaseURL: mirrorURL
            ),
            mirrorURL
        )
        XCTAssertNil(
            CustomLLMModelDownloadSupport.fallbackHubBaseURL(
                from: mirrorURL,
                mirrorBaseURL: mirrorURL
            )
        )
    }

    func testInFlightBytesUsesReportedProgressWhenAvailable() {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 42

        let current = CustomLLMModelDownloadSupport.inFlightBytes(
            progress: progress,
            expectedFileBytes: 1_024,
            startTime: Date().addingTimeInterval(-5)
        )

        XCTAssertEqual(current, 42)
    }

    func testInFlightBytesEstimatesProgressWhenProgressStillZero() {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 0

        let current = CustomLLMModelDownloadSupport.inFlightBytes(
            progress: progress,
            expectedFileBytes: 20 * 1024 * 1024,
            startTime: Date().addingTimeInterval(-10)
        )

        XCTAssertGreaterThan(current, 0)
        XCTAssertLessThan(current, Int64(Double(20 * 1024 * 1024) * 0.95) + 1)
    }
}
