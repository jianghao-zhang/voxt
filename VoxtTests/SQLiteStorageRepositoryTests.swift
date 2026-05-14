import XCTest
@testable import Voxt

@MainActor
final class SQLiteStorageRepositoryTests: XCTestCase {
    private static var retainedObjects: [AnyObject] = []
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        // Keep temporary databases alive until the XCTest process exits. GRDB owns
        // SQLite resources that can outlive individual test methods under the
        // hosted macOS test runner.
        temporaryURLs = []
        try super.tearDownWithError()
    }

    func testFreshDatabaseCreatesStorageTablesAndIndexes() throws {
        let database = try makeDatabase()

        let tables = try database.debugSQLiteObjectNames(type: "table")
        XCTAssertTrue(tables.contains("dictionary_entries"))
        XCTAssertTrue(tables.contains("dictionary_replacement_terms"))
        XCTAssertTrue(tables.contains("dictionary_observed_variants"))
        XCTAssertTrue(tables.contains("history_entries"))
        XCTAssertTrue(tables.contains("dictionary_search"))
        XCTAssertTrue(tables.contains("history_search"))

        let indexes = try database.debugSQLiteObjectNames(type: "index")
        XCTAssertTrue(indexes.contains("idx_dictionary_normalized_scope"))
        XCTAssertTrue(indexes.contains("idx_history_kind_created"))
    }

    func testDictionaryJSONMigrationPreservesEntryDetailsAndBacksUpLegacyFile() throws {
        let database = try makeDatabase()
        let legacyURL = try makeTemporaryDirectory().appendingPathComponent("dictionary.json")
        let groupID = UUID()
        let entry = DictionaryEntry(
            term: "Voxt Term",
            normalizedTerm: "voxt term",
            groupID: groupID,
            groupNameSnapshot: "Focused Group",
            source: .auto,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            lastMatchedAt: Date(timeIntervalSince1970: 30),
            matchCount: 7,
            observedVariants: [
                ObservedVariant(
                    text: "voxt variant",
                    normalizedText: "voxt variant",
                    count: 3,
                    lastSeenAt: Date(timeIntervalSince1970: 40),
                    confidence: .high
                )
            ],
            replacementTerms: [
                DictionaryReplacementTerm(text: "Alias Term", normalizedText: "alias term")
            ]
        )
        try JSONEncoder().encode([entry]).write(to: legacyURL)

        let repository = retain(DictionaryRepository(database: database, legacyJSONURL: legacyURL))
        let migratedEntries = try repository.allEntries()

        XCTAssertEqual(migratedEntries.count, 1)
        XCTAssertEqual(migratedEntries[0].term, "Voxt Term")
        XCTAssertEqual(migratedEntries[0].groupID, groupID)
        XCTAssertEqual(migratedEntries[0].groupNameSnapshot, "Focused Group")
        XCTAssertEqual(migratedEntries[0].source, .auto)
        XCTAssertEqual(migratedEntries[0].lastMatchedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(migratedEntries[0].matchCount, 7)
        XCTAssertEqual(migratedEntries[0].replacementTerms.map(\.text), ["Alias Term"])
        XCTAssertEqual(migratedEntries[0].observedVariants.map(\.text), ["voxt variant"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path + ".migrated-backup"))
    }

    func testDictionaryDuplicateChecksUseDatabaseIndexes() throws {
        let database = try makeDatabase()
        let repository = retain(DictionaryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let groupID = UUID()
        let entry = DictionaryEntry(
            term: "Primary",
            normalizedTerm: "primary",
            groupID: groupID,
            groupNameSnapshot: "Group",
            source: .manual,
            replacementTerms: [
                DictionaryReplacementTerm(text: "Alias", normalizedText: "alias")
            ]
        )

        try repository.replaceAll([entry])

        XCTAssertTrue(try repository.hasEntry(normalizedTerm: "primary", activeGroupID: groupID))
        XCTAssertTrue(try repository.hasEntry(normalizedTerm: "alias", activeGroupID: groupID))
        XCTAssertFalse(try repository.hasEntry(normalizedTerm: "alias", activeGroupID: nil))
    }

    func testDictionaryUpsertDoesNotReplaceExistingEntryOnUniqueTermConflict() throws {
        let database = try makeDatabase()
        let repository = retain(DictionaryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let groupID = UUID()
        let original = DictionaryEntry(
            term: "Primary",
            normalizedTerm: "primary",
            groupID: groupID,
            groupNameSnapshot: "Group",
            source: .manual,
            observedVariants: [
                ObservedVariant(
                    text: "Observed Primary",
                    normalizedText: "observed primary",
                    count: 4,
                    lastSeenAt: Date(timeIntervalSince1970: 40),
                    confidence: .high
                )
            ],
            replacementTerms: [
                DictionaryReplacementTerm(text: "Alias", normalizedText: "alias")
            ]
        )
        let duplicate = DictionaryEntry(
            term: "Duplicate Primary",
            normalizedTerm: "primary",
            groupID: groupID,
            groupNameSnapshot: "Group",
            source: .auto
        )

        try repository.replaceAll([original])
        XCTAssertThrowsError(try repository.upsert(duplicate))

        let persisted = try XCTUnwrap(repository.allEntries().first { $0.id == original.id })
        XCTAssertEqual(persisted.term, "Primary")
        XCTAssertEqual(persisted.replacementTerms.map(\.text), ["Alias"])
        XCTAssertEqual(persisted.observedVariants.map(\.text), ["Observed Primary"])
        XCTAssertFalse(try repository.allEntries().contains { $0.id == duplicate.id })
    }

    func testDictionaryUpsertDoesNotReplaceExistingAliasOnUniqueAliasConflict() throws {
        let database = try makeDatabase()
        let repository = retain(DictionaryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let groupID = UUID()
        let first = DictionaryEntry(
            term: "First",
            normalizedTerm: "first",
            groupID: groupID,
            source: .manual,
            replacementTerms: [
                DictionaryReplacementTerm(text: "Shared Alias", normalizedText: "shared alias")
            ]
        )
        var second = DictionaryEntry(
            term: "Second",
            normalizedTerm: "second",
            groupID: groupID,
            source: .manual
        )

        try repository.replaceAll([first, second])
        second.replacementTerms = [
            DictionaryReplacementTerm(text: "Shared Alias", normalizedText: "shared alias")
        ]
        XCTAssertThrowsError(try repository.upsert(second))

        let persistedEntries = try repository.allEntries()
        let persistedFirst = try XCTUnwrap(persistedEntries.first { $0.id == first.id })
        let persistedSecond = try XCTUnwrap(persistedEntries.first { $0.id == second.id })
        XCTAssertEqual(persistedFirst.replacementTerms.map(\.text), ["Shared Alias"])
        XCTAssertEqual(persistedSecond.replacementTerms, [])
    }

    func testHistoryJSONMigrationPreservesTranscriptEntriesAndBacksUpLegacyFile() throws {
        let database = try makeDatabase()
        let legacyURL = try makeTemporaryDirectory().appendingPathComponent("transcription-history.json")
        let normalEntry = makeHistoryEntry(
            text: "visible history",
            createdAt: Date(timeIntervalSince1970: 1),
            kind: .normal
        )
        let transcriptEntry = makeHistoryEntry(
            text: "transcript history",
            createdAt: Date(timeIntervalSince1970: 2),
            kind: .transcript
        )
        try JSONEncoder().encode([normalEntry, transcriptEntry]).write(to: legacyURL)

        let repository = retain(HistoryRepository(database: database, legacyJSONURL: legacyURL))

        XCTAssertEqual(try repository.entryCount(kind: nil), 2)
        XCTAssertEqual(try repository.entryCount(kind: .normal), 1)
        XCTAssertEqual(try repository.entryCount(kind: .transcript), 1)
        XCTAssertEqual(try repository.entry(id: transcriptEntry.id)?.text, "transcript history")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path + ".migrated-backup"))
    }

    func testHistoryRepositoryPaginatesSearchesAndDeletes() throws {
        let database = try makeDatabase()
        let repository = retain(HistoryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let oldID = UUID()
        let entries = [
            makeHistoryEntry(
                id: oldID,
                text: "old history",
                createdAt: Date(timeIntervalSince1970: 1),
                kind: .normal
            ),
            makeHistoryEntry(
                text: "translation history",
                createdAt: Date(timeIntervalSince1970: 2),
                kind: .translation
            ),
            makeHistoryEntry(
                text: "needle focused app entry",
                createdAt: Date(timeIntervalSince1970: 3),
                kind: .normal,
                focusedAppName: "Safari",
                dictionaryHitTerms: ["NeedleTerm"]
            )
        ]

        try repository.replaceAll(entries)

        XCTAssertEqual(try repository.entryCount(kind: .normal), 2)
        XCTAssertEqual(
            try repository.entries(kind: .normal, limit: 1, offset: 0).map(\.text),
            ["needle focused app entry"]
        )
        XCTAssertEqual(
            try repository.entries(kind: nil, query: "NeedleTerm", limit: 10, offset: 0).map(\.text),
            ["needle focused app entry"]
        )
        XCTAssertEqual(
            try repository.entries(kind: nil, query: "Safari", limit: 10, offset: 0).map(\.text),
            ["needle focused app entry"]
        )

        let removed = try repository.deleteEntries(olderThan: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(removed.map(\.id), [oldID])
        XCTAssertNil(try repository.entry(id: oldID))
    }

    func testHistoryReportMetricsUseDatabaseAggregates() throws {
        let database = try makeDatabase()
        let repository = retain(HistoryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayStarts = [yesterday, today]

        try repository.replaceAll([
            makeHistoryEntry(
                text: "abcd",
                createdAt: today.addingTimeInterval(60),
                kind: .normal,
                audioDurationSeconds: 10
            ),
            makeHistoryEntry(
                text: "translation",
                createdAt: yesterday.addingTimeInterval(60),
                kind: .translation,
                audioDurationSeconds: 20
            )
        ])

        let metrics = try repository.reportMetrics(dayStarts: dayStarts)

        XCTAssertEqual(metrics.totalDictationSeconds, 30)
        XCTAssertEqual(metrics.totalCharacters, 15)
        XCTAssertEqual(metrics.totalTranslationCharacters, 11)
        XCTAssertEqual(metrics.dailyCharacters[today], 4)
        XCTAssertEqual(metrics.dailyCharacters[yesterday], 11)
    }

    func testRepositoryHandlesLargeBatchedDictionaryAndHistoryData() throws {
        let database = try makeDatabase()
        let dictionaryRepository = retain(DictionaryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))
        let historyRepository = retain(HistoryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false))

        let dictionaryEntries = (0..<20_000).map {
            DictionaryEntry(
                term: "Term\($0)",
                normalizedTerm: "term\($0)",
                source: .manual,
                replacementTerms: [
                    DictionaryReplacementTerm(text: "Alias\($0)", normalizedText: "alias\($0)")
                ]
            )
        }
        try dictionaryRepository.replaceAll(dictionaryEntries)
        XCTAssertEqual(try dictionaryRepository.entryCount(query: "Alias19999"), 1)

        let historyEntries = (0..<20_000).map {
            makeHistoryEntry(
                text: $0 == 19_999 ? "needle history row" : "history row \($0)",
                createdAt: Date(timeIntervalSince1970: TimeInterval($0)),
                kind: $0.isMultiple(of: 2) ? .normal : .translation
            )
        }
        try historyRepository.replaceAll(historyEntries)

        XCTAssertEqual(try historyRepository.entryCount(kind: .normal), 10_000)
        XCTAssertEqual(
            try historyRepository.entries(kind: nil, query: "needle", limit: 10, offset: 0).map(\.text),
            ["needle history row"]
        )
        XCTAssertEqual(try historyRepository.entries(kind: .translation, limit: 25, offset: 50).count, 25)
    }
}

private extension SQLiteStorageRepositoryTests {
    func makeDatabase() throws -> VoxtDatabase {
        let directory = try makeTemporaryDirectory()
        let database = VoxtDatabase(databaseURL: directory.appendingPathComponent("voxt.sqlite"))
        return retain(database)
    }

    func retain<Value: AnyObject>(_ value: Value) -> Value {
        Self.retainedObjects.append(value)
        return value
    }

    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-storage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    func makeHistoryEntry(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        kind: TranscriptionHistoryKind,
        audioDurationSeconds: TimeInterval? = nil,
        focusedAppName: String? = nil,
        dictionaryHitTerms: [String] = []
    ) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
            transcriptionEngine: "engine",
            transcriptionModel: "model",
            enhancementMode: "mode",
            enhancementModel: "enhanced",
            kind: kind,
            isTranslation: kind == .translation,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: focusedAppName,
            focusedAppBundleID: focusedAppName.map { "com.example.\($0.lowercased())" },
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            audioRelativePath: nil,
            whisperWordTimings: nil,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )
    }
}
