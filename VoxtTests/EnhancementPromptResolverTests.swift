import XCTest
@testable import Voxt

final class EnhancementPromptResolverTests: XCTestCase {
    func testDisabledAppBranchFallsBackToGlobalPrompt() {
        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Clean {{RAW_TRANSCRIPTION}} for {{USER_MAIN_LANGUAGE}}",
                rawTranscription: "hello",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: "- OpenAI",
                appEnhancementEnabled: false,
                groups: [],
                urlsByID: [:],
                frontmostBundleID: nil,
                focusedAppName: "Notes",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertEqual(output.delivery, .systemPrompt)
        XCTAssertEqual(output.promptContext.focusedAppName, "Notes")
        XCTAssertContains(output.content, "Clean hello for English")
        XCTAssertContains(output.content, "It is not a target output language and must not trigger translation.")
        XCTAssertContains(output.content, "Dictionary Guidance")
        XCTAssertEqual(output.source, .globalDefault(.appBranchDisabled))
    }

    func testBrowserURLMatchUsesGroupPromptAndUserMessageDelivery() {
        let docsID = UUID()
        let docsGroup = TestFactories.makeAppBranchGroup(
            name: "Docs",
            prompt: "Docs {{RAW_TRANSCRIPTION}} {{USER_MAIN_LANGUAGE}}",
            urlPatternIDs: [docsID]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "fix this",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: "Chinese",
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [docsGroup],
                urlsByID: [docsID: "example.com/docs/*"],
                frontmostBundleID: "com.google.Chrome",
                focusedAppName: "Google Chrome",
                normalizedActiveURL: "example.com/docs/page",
                supportedBrowserBundleIDs: ["com.google.Chrome"]
            )
        )

        XCTAssertEqual(output.delivery, .userMessage)
        XCTAssertEqual(output.promptContext.matchedGroupID, docsGroup.id)
        XCTAssertEqual(output.promptContext.matchedURLGroupName, "Docs")
        XCTAssertContains(output.content, "Docs fix this English")
        XCTAssertContains(output.content, "Other frequently used user languages: Chinese.")
    }

    func testBrowserWithoutURLFallsBackAndKeepsContextEmpty() {
        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "fix this",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [TestFactories.makeAppBranchGroup(name: "Docs", prompt: "Prompt")],
                urlsByID: [:],
                frontmostBundleID: "com.google.Chrome",
                focusedAppName: "Google Chrome",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: ["com.google.Chrome"]
            )
        )

        XCTAssertEqual(output.delivery, .systemPrompt)
        XCTAssertNil(output.promptContext.matchedGroupID)
        XCTAssertEqual(output.source, .globalDefault(.browserURLUnavailable(bundleID: "com.google.Chrome")))
    }

    func testAppGroupMatchUsesAppPrompt() {
        let group = TestFactories.makeAppBranchGroup(
            name: "Xcode",
            prompt: "Xcode {{RAW_TRANSCRIPTION}}",
            appBundleIDs: ["com.apple.dt.Xcode"]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "rewrite",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [group],
                urlsByID: [:],
                frontmostBundleID: "com.apple.dt.Xcode",
                focusedAppName: "Xcode",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertEqual(output.delivery, .userMessage)
        XCTAssertEqual(output.promptContext.matchedAppGroupName, "Xcode")
        XCTAssertContains(output.content, "Xcode rewrite")
    }

    func testAppGroupWithEmptyPromptSkipsEnhancementButKeepsMatchedContext() {
        let group = TestFactories.makeAppBranchGroup(
            name: "Xcode",
            prompt: "   ",
            appBundleIDs: ["com.apple.dt.Xcode"]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global {{RAW_TRANSCRIPTION}}",
                rawTranscription: "rewrite",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: "- OpenAI",
                appEnhancementEnabled: true,
                groups: [group],
                urlsByID: [:],
                frontmostBundleID: "com.apple.dt.Xcode",
                focusedAppName: "Xcode",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertEqual(output.delivery, .skipEnhancement)
        XCTAssertEqual(output.promptContext.matchedGroupID, group.id)
        XCTAssertEqual(output.promptContext.matchedAppGroupName, "Xcode")
        XCTAssertEqual(output.source, .appGroupPromptDisabled(groupName: "Xcode", bundleID: "com.apple.dt.Xcode"))
        XCTAssertEqual(output.content, "")
    }

    func testBrowserURLMatchWithEmptyPromptSkipsEnhancementButKeepsMatchedContext() {
        let docsID = UUID()
        let docsGroup = TestFactories.makeAppBranchGroup(
            name: "Docs",
            prompt: "",
            urlPatternIDs: [docsID]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global {{RAW_TRANSCRIPTION}}",
                rawTranscription: "fix this",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: "- OpenAI",
                appEnhancementEnabled: true,
                groups: [docsGroup],
                urlsByID: [docsID: "example.com/docs/*"],
                frontmostBundleID: "com.google.Chrome",
                focusedAppName: "Google Chrome",
                normalizedActiveURL: "example.com/docs/page",
                supportedBrowserBundleIDs: ["com.google.Chrome"]
            )
        )

        XCTAssertEqual(output.delivery, .skipEnhancement)
        XCTAssertEqual(output.promptContext.matchedGroupID, docsGroup.id)
        XCTAssertEqual(output.promptContext.matchedURLGroupName, "Docs")
        XCTAssertEqual(
            output.source,
            .urlGroupPromptDisabled(
                groupName: "Docs",
                pattern: "example.com/docs/*",
                url: "example.com/docs/page"
            )
        )
        XCTAssertEqual(output.content, "")
    }

    func testLanguagePreservationRulesTreatMainLanguageAsGuidanceOnly() {
        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Clean {{RAW_TRANSCRIPTION}} for {{USER_MAIN_LANGUAGE}}",
                rawTranscription: "你好 world",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: "Chinese",
                dictionaryGlossary: nil,
                appEnhancementEnabled: false,
                groups: [],
                urlsByID: [:],
                frontmostBundleID: nil,
                focusedAppName: "Notes",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertContains(output.content, "User main language: English.")
        XCTAssertContains(output.content, "Other frequently used user languages: Chinese.")
        XCTAssertContains(output.content, "If the raw transcription is in another user language or mixes multiple user languages, preserve the original language distribution and wording.")
        XCTAssertContains(output.content, "Enhancement must not translate, summarize, paraphrase, or rewrite the text into the user main language.")
    }

    func testAppGroupPromptAlsoAppendsLanguagePreservationRules() {
        let group = TestFactories.makeAppBranchGroup(
            name: "Docs",
            prompt: "Docs {{RAW_TRANSCRIPTION}}",
            appBundleIDs: ["com.example.docs"]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "bonjour",
                userMainLanguagePromptValue: "English",
                userOtherLanguagesPromptValue: DictionaryHistoryScanPromptLanguageSupport.noneValue,
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [group],
                urlsByID: [:],
                frontmostBundleID: "com.example.docs",
                focusedAppName: "Docs",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertContains(output.content, "Docs bonjour")
        XCTAssertContains(output.content, "Other frequently used user languages: None.")
        XCTAssertContains(output.content, "It is not a target output language and must not trigger translation.")
    }
}
