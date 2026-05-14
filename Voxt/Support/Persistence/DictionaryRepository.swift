import Foundation
import GRDB

protocol DictionaryRepositoryProtocol: AnyObject, Sendable {
    func allEntries() throws -> [DictionaryEntry]
    func allTerms(limit: Int?) throws -> [String]
    func entries(filter: DictionaryFilter, query: String, limit: Int, offset: Int) throws -> [DictionaryEntry]
    func entryCount(filter: DictionaryFilter, query: String) throws -> Int
    func upsert(_ entry: DictionaryEntry) throws
    func replaceAll(_ entries: [DictionaryEntry]) throws
    func delete(id: UUID) throws
    func clearAll() throws
    func hasEntry(normalizedTerm: String, activeGroupID: UUID?) throws -> Bool
}

final class DictionaryRepository: DictionaryRepositoryProtocol, @unchecked Sendable {
    private let database: VoxtDatabase
    private let fileManager: FileManager
    private let legacyJSONURL: URL?

    init(
        database: VoxtDatabase = .shared,
        fileManager: FileManager = .default,
        legacyJSONURL: URL? = nil,
        migrateLegacyJSON: Bool = true
    ) {
        self.database = database
        self.fileManager = fileManager
        self.legacyJSONURL = legacyJSONURL ?? Self.defaultLegacyJSONURL(fileManager: fileManager)

        if migrateLegacyJSON {
            migrateLegacyJSONIfNeeded()
        }
    }

    func allEntries() throws -> [DictionaryEntry] {
        try fetchEntries(
            sql: "SELECT id FROM dictionary_entries ORDER BY updatedAt DESC, term COLLATE NOCASE ASC",
            arguments: []
        )
    }

    func allTerms(limit: Int? = nil) throws -> [String] {
        try database.dbQueue.read { db in
            var sql = "SELECT term FROM dictionary_entries ORDER BY term COLLATE NOCASE ASC"
            var arguments: StatementArguments = []
            if let limit {
                sql += " LIMIT ?"
                arguments += [limit]
            }
            return try String.fetchAll(
                db,
                sql: sql,
                arguments: arguments
            )
        }
    }

    func entries(filter: DictionaryFilter, query: String = "", limit: Int, offset: Int) throws -> [DictionaryEntry] {
        var whereClauses: [String] = []
        var arguments: StatementArguments = []

        switch filter {
        case .all:
            break
        case .autoAdded:
            whereClauses.append("source = ?")
            arguments += [DictionaryEntrySource.auto.rawValue]
        case .manualAdded:
            whereClauses.append("source = ?")
            arguments += [DictionaryEntrySource.manual.rawValue]
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ftsQuery = VoxtFTSQueryBuilder.query(from: trimmedQuery) {
            let searchIDs = try database.dbQueue.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT entryID FROM dictionary_search WHERE dictionary_search MATCH ?",
                    arguments: [ftsQuery]
                )
            }
            if searchIDs.isEmpty {
                return []
            }
            whereClauses.append("id IN \(sqlPlaceholders(count: searchIDs.count))")
            arguments += StatementArguments(searchIDs)
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        arguments += [limit, offset]

        return try fetchEntries(
            sql: """
                SELECT id FROM dictionary_entries
                \(whereSQL)
                ORDER BY updatedAt DESC, term COLLATE NOCASE ASC
                LIMIT ? OFFSET ?
                """,
            arguments: arguments
        )
    }

    func entryCount(filter: DictionaryFilter = .all, query: String = "") throws -> Int {
        var whereClauses: [String] = []
        var arguments: StatementArguments = []

        switch filter {
        case .all:
            break
        case .autoAdded:
            whereClauses.append("source = ?")
            arguments += [DictionaryEntrySource.auto.rawValue]
        case .manualAdded:
            whereClauses.append("source = ?")
            arguments += [DictionaryEntrySource.manual.rawValue]
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ftsQuery = VoxtFTSQueryBuilder.query(from: trimmedQuery) {
            let searchIDs = try database.dbQueue.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT entryID FROM dictionary_search WHERE dictionary_search MATCH ?",
                    arguments: [ftsQuery]
                )
            }
            if searchIDs.isEmpty {
                return 0
            }
            whereClauses.append("id IN \(sqlPlaceholders(count: searchIDs.count))")
            arguments += StatementArguments(searchIDs)
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        return try database.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictionary_entries \(whereSQL)",
                arguments: arguments
            ) ?? 0
        }
    }

    func upsert(_ entry: DictionaryEntry) throws {
        try database.dbQueue.write { db in
            try upsert(entry, db: db)
        }
    }

    func replaceAll(_ entries: [DictionaryEntry]) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dictionary_search")
            try db.execute(sql: "DELETE FROM dictionary_observed_variants")
            try db.execute(sql: "DELETE FROM dictionary_replacement_terms")
            try db.execute(sql: "DELETE FROM dictionary_entries")
            for entry in entries {
                try upsert(entry, db: db)
            }
        }
    }

    func upsertAll(_ entries: [DictionaryEntry]) throws {
        try database.dbQueue.write { db in
            for entry in entries {
                try upsert(entry, db: db)
            }
        }
    }

    func delete(id: UUID) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dictionary_search WHERE entryID = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM dictionary_entries WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func clearAll() throws {
        try replaceAll([])
    }

    func hasEntry(normalizedTerm: String, activeGroupID: UUID?) throws -> Bool {
        let group = activeGroupID?.uuidString ?? ""
        return try database.dbQueue.read { db in
            let entryCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM dictionary_entries
                    WHERE COALESCE(groupID, '') = ? AND normalizedTerm = ?
                    """,
                arguments: [group, normalizedTerm]
            ) ?? 0
            if entryCount > 0 {
                return true
            }
            let replacementCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM dictionary_replacement_terms r
                    JOIN dictionary_entries e ON e.id = r.entryID
                    WHERE COALESCE(e.groupID, '') = ? AND r.normalizedText = ?
                    """,
                arguments: [group, normalizedTerm]
            ) ?? 0
            return replacementCount > 0
        }
    }

    private func fetchEntries(sql: String, arguments: StatementArguments) throws -> [DictionaryEntry] {
        try database.dbQueue.read { db in
            let ids = try String.fetchAll(db, sql: sql, arguments: arguments)
            guard !ids.isEmpty else { return [] }
            return try entries(for: ids, db: db)
        }
    }

    private func entries(for ids: [String], db: Database) throws -> [DictionaryEntry] {
        var entries: [DictionaryEntry] = []
        entries.reserveCapacity(ids.count)

        for id in ids {
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM dictionary_entries WHERE id = ?",
                arguments: [id]
            ) else {
                continue
            }

            let replacements = try Row.fetchAll(
                db,
                sql: "SELECT * FROM dictionary_replacement_terms WHERE entryID = ? ORDER BY text COLLATE NOCASE ASC",
                arguments: [id]
            ).compactMap { replacement(from: $0) }

            let variants = try Row.fetchAll(
                db,
                sql: "SELECT * FROM dictionary_observed_variants WHERE entryID = ? ORDER BY count DESC, lastSeenAt DESC",
                arguments: [id]
            ).compactMap { observedVariant(from: $0) }

            entries.append(entry(from: row, replacementTerms: replacements, observedVariants: variants))
        }

        return entries
    }

    private func upsert(_ entry: DictionaryEntry, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO dictionary_entries (
                    id, term, normalizedTerm, groupID, groupNameSnapshot, source, status,
                    createdAt, updatedAt, lastMatchedAt, matchCount
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    term = excluded.term,
                    normalizedTerm = excluded.normalizedTerm,
                    groupID = excluded.groupID,
                    groupNameSnapshot = excluded.groupNameSnapshot,
                    source = excluded.source,
                    status = excluded.status,
                    createdAt = excluded.createdAt,
                    updatedAt = excluded.updatedAt,
                    lastMatchedAt = excluded.lastMatchedAt,
                    matchCount = excluded.matchCount
                """,
            arguments: VoxtDatabaseArguments.make([
                entry.id.uuidString,
                entry.term,
                entry.normalizedTerm,
                entry.groupID?.uuidString,
                entry.groupNameSnapshot,
                entry.source.rawValue,
                entry.status.rawValue,
                entry.createdAt.timeIntervalSince1970,
                entry.updatedAt.timeIntervalSince1970,
                entry.lastMatchedAt?.timeIntervalSince1970,
                entry.matchCount
            ])
        )

        try db.execute(sql: "DELETE FROM dictionary_replacement_terms WHERE entryID = ?", arguments: [entry.id.uuidString])
        for replacement in entry.replacementTerms {
            try db.execute(
                sql: """
                    INSERT INTO dictionary_replacement_terms
                    (id, entryID, groupID, text, normalizedText) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        entryID = excluded.entryID,
                        groupID = excluded.groupID,
                        text = excluded.text,
                        normalizedText = excluded.normalizedText
                    """,
                arguments: VoxtDatabaseArguments.make([
                    replacement.id.uuidString,
                    entry.id.uuidString,
                    entry.groupID?.uuidString,
                    replacement.text,
                    replacement.normalizedText
                ])
            )
        }

        try db.execute(sql: "DELETE FROM dictionary_observed_variants WHERE entryID = ?", arguments: [entry.id.uuidString])
        for variant in entry.observedVariants {
            try db.execute(
                sql: """
                    INSERT INTO dictionary_observed_variants
                    (id, entryID, text, normalizedText, count, lastSeenAt, confidence)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        entryID = excluded.entryID,
                        text = excluded.text,
                        normalizedText = excluded.normalizedText,
                        count = excluded.count,
                        lastSeenAt = excluded.lastSeenAt,
                        confidence = excluded.confidence
                    """,
                arguments: VoxtDatabaseArguments.make([
                    variant.id.uuidString,
                    entry.id.uuidString,
                    variant.text,
                    variant.normalizedText,
                    variant.count,
                    variant.lastSeenAt.timeIntervalSince1970,
                    variant.confidence.rawValue
                ])
            )
        }

        try db.execute(sql: "DELETE FROM dictionary_search WHERE entryID = ?", arguments: [entry.id.uuidString])
        try db.execute(
            sql: """
                INSERT INTO dictionary_search (entryID, term, aliases, variants, groupName)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: VoxtDatabaseArguments.make([
                entry.id.uuidString,
                entry.term,
                entry.replacementTerms.map(\.text).joined(separator: " "),
                entry.observedVariants.map(\.text).joined(separator: " "),
                entry.groupNameSnapshot ?? ""
            ])
        )
    }

    private func entry(
        from row: Row,
        replacementTerms: [DictionaryReplacementTerm],
        observedVariants: [ObservedVariant]
    ) -> DictionaryEntry {
        let id: String = row["id"]
        let term: String = row["term"]
        let normalizedTerm: String = row["normalizedTerm"]
        let source: String = row["source"]
        let createdAt: Double = row["createdAt"]
        let updatedAt: Double = row["updatedAt"]
        let matchCount: Int = row["matchCount"]
        let status: String = row["status"]
        return DictionaryEntry(
            id: UUID(uuidString: id) ?? UUID(),
            term: term,
            normalizedTerm: normalizedTerm,
            groupID: (row["groupID"] as String?).flatMap(UUID.init(uuidString:)),
            groupNameSnapshot: row["groupNameSnapshot"],
            source: DictionaryEntrySource(rawValue: source) ?? .manual,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            lastMatchedAt: (row["lastMatchedAt"] as Double?).map(Date.init(timeIntervalSince1970:)),
            matchCount: matchCount,
            status: DictionaryEntryStatus(rawValue: status) ?? .active,
            observedVariants: observedVariants,
            replacementTerms: replacementTerms
        )
    }

    private func replacement(from row: Row) -> DictionaryReplacementTerm? {
        let idText: String = row["id"]
        guard let id = UUID(uuidString: idText) else { return nil }
        let text: String = row["text"]
        let normalizedText: String = row["normalizedText"]
        return DictionaryReplacementTerm(
            id: id,
            text: text,
            normalizedText: normalizedText
        )
    }

    private func observedVariant(from row: Row) -> ObservedVariant? {
        let idText: String = row["id"]
        guard let id = UUID(uuidString: idText) else { return nil }
        let text: String = row["text"]
        let normalizedText: String = row["normalizedText"]
        let count: Int = row["count"]
        let lastSeenAt: Double = row["lastSeenAt"]
        let confidence: String = row["confidence"]
        return ObservedVariant(
            id: id,
            text: text,
            normalizedText: normalizedText,
            count: count,
            lastSeenAt: Date(timeIntervalSince1970: lastSeenAt),
            confidence: DictionaryVariantConfidence(rawValue: confidence) ?? .medium
        )
    }

    private func migrateLegacyJSONIfNeeded() {
        do {
            let existingCount = try database.dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_entries") ?? 0
            }
            guard existingCount == 0,
                  let legacyJSONURL,
                  fileManager.fileExists(atPath: legacyJSONURL.path)
            else {
                return
            }

            let data = try Data(contentsOf: legacyJSONURL)
            let entries = try VoxtPersistenceCoding.decoder.decode([DictionaryEntry].self, from: data)
            try replaceAll(entries)
            try backupLegacyJSON(at: legacyJSONURL)
        } catch {
            VoxtLog.warning("Dictionary SQLite migration skipped or failed: \(error.localizedDescription)")
        }
    }

    private func backupLegacyJSON(at url: URL) throws {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).migrated-backup")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.moveItem(at: url, to: backupURL)
    }

    private static func defaultLegacyJSONURL(fileManager: FileManager) -> URL? {
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    private func sqlPlaceholders(count: Int) -> String {
        "(\(Array(repeating: "?", count: count).joined(separator: ",")))"
    }
}
