import XCTest
@testable import Voxt

@MainActor
final class SessionTextIOTests: XCTestCase {
    func testRewriteAlwaysPresentsAnswerOverlay() {
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testOnlyDirectAnswerRewriteUsesStructuredOutput() {
        XCTAssertTrue(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testNonRewriteSessionsDoNotPresentRewriteAnswerOverlay() {
        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )

        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
    }

    func testSelectedTextTranslationAlwaysUsesAnswerOverlayAfterTranslation() {
        XCTAssertTrue(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .transcription,
                isSelectedTextTranslationFlow: true
            )
        )
    }

    func testSelectedTextTranslationAutoInjectRequiresFocusedInput() {
        XCTAssertTrue(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                hadWritableFocusedInput: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                hadWritableFocusedInput: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                hadWritableFocusedInput: true
            )
        )
    }
}
