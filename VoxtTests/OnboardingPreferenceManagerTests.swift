import XCTest
@testable import Voxt

final class OnboardingPreferenceManagerTests: XCTestCase {
    func testResolvedCompletionStateDefaultsToFalseForFreshInstall() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, false)
    }

    func testResolvedCompletionStateTreatsExistingPersistentDomainAsCompleted() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)
        defaults.setPersistentDomain(
            [AppPreferenceKey.translationTargetLanguage: TranslationTargetLanguage.english.rawValue],
            forName: suiteName
        )

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
    }

    func testResolvedCompletionStateTreatsExistingAppSupportDirectoryAsCompleted() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let appSupportDirectory = directory.url.appendingPathComponent("Voxt", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
    }

    func testMarkCompletedClearsSavedStep() {
        let defaults = TestDoubles.makeUserDefaults()
        OnboardingPreferenceManager.saveLastStep(.meeting, defaults: defaults)

        OnboardingPreferenceManager.markCompleted(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
        XCTAssertNil(defaults.string(forKey: AppPreferenceKey.onboardingLastStepID))
    }

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "VoxtTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private final class TestAppSupportFileManager: FileManager {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func url(
        for directory: SearchPathDirectory,
        in domain: SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory, domain == .userDomainMask {
            return applicationSupportDirectory
        }
        return try super.url(
            for: directory,
            in: domain,
            appropriateFor: url,
            create: shouldCreate
        )
    }
}
