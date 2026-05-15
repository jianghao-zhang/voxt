import XCTest
@testable import Voxt

final class ConfigurationTransferManagerTests: XCTestCase {
    func testBetaUpdatesEnabledExportsAndImports() throws {
        let sourceDefaults = TestDoubles.makeUserDefaults(testName: #function + ".source")
        let destinationDefaults = TestDoubles.makeUserDefaults(testName: #function + ".destination")
        let directory = try TemporaryDirectory()
        let environment = TestEnvironmentFactory.configurationTransferEnvironment(in: directory)
        sourceDefaults.set(true, forKey: AppPreferenceKey.betaUpdatesEnabled)

        let exported = try ConfigurationTransferManager.exportJSONString(
            defaults: sourceDefaults,
            environment: environment
        )
        try ConfigurationTransferManager.importConfiguration(
            from: exported,
            defaults: destinationDefaults,
            environment: environment
        )

        XCTAssertEqual(destinationDefaults.object(forKey: AppPreferenceKey.betaUpdatesEnabled) as? Bool, true)
    }

    func testMissingBetaUpdatesEnabledFieldImportsAsDisabled() throws {
        let sourceDefaults = TestDoubles.makeUserDefaults(testName: #function + ".source")
        let destinationDefaults = TestDoubles.makeUserDefaults(testName: #function + ".destination")
        let directory = try TemporaryDirectory()
        let environment = TestEnvironmentFactory.configurationTransferEnvironment(in: directory)
        sourceDefaults.set(true, forKey: AppPreferenceKey.betaUpdatesEnabled)
        destinationDefaults.set(true, forKey: AppPreferenceKey.betaUpdatesEnabled)

        let exported = try ConfigurationTransferManager.exportJSONString(
            defaults: sourceDefaults,
            environment: environment
        )
        let legacyExport = try exportJSONByRemovingBetaUpdatesEnabled(from: exported)

        try ConfigurationTransferManager.importConfiguration(
            from: legacyExport,
            defaults: destinationDefaults,
            environment: environment
        )

        XCTAssertEqual(destinationDefaults.object(forKey: AppPreferenceKey.betaUpdatesEnabled) as? Bool, false)
    }

    private func exportJSONByRemovingBetaUpdatesEnabled(from json: String) throws -> String {
        let data = Data(json.utf8)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var general = object["general"] as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        general.removeValue(forKey: "betaUpdatesEnabled")
        object["general"] = general
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let legacyJSON = String(data: legacyData, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return legacyJSON
    }
}
