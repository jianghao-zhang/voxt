import XCTest
@testable import Voxt

final class RemoteProviderConnectivityTesterTests: XCTestCase {
    func testDeepSeekReachabilityBodyDisablesThinkingAndLimitsOutput() throws {
        let tester = RemoteProviderConnectivityTester(testTarget: .llm(.deepseek))

        let body = tester.openAICompatibleReachabilityBody(
            provider: .deepseek,
            endpoint: "https://api.deepseek.com/chat/completions",
            model: "deepseek-v4-flash"
        )

        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        XCTAssertEqual(body["stream"] as? Bool, false)

        let thinking = try XCTUnwrap(body["thinking"] as? [String: String])
        XCTAssertEqual(thinking["type"], "disabled")
    }
}
