import Foundation
import Combine

enum DictionaryEntrySource: String, Codable, CaseIterable {
    case manual
    case auto

    var titleKey: String {
        switch self {
        case .manual:
            return "Manual"
        case .auto:
            return "Auto"
        }
    }
}

enum DictionaryEntryStatus: String, Codable {
    case active
    case disabled
}

enum DictionaryVariantConfidence: String, Codable {
    case high
    case medium
    case low
}

enum DictionaryFilter: String, CaseIterable, Identifiable {
    case all
    case autoAdded
    case manualAdded

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all:
            return "All"
        case .autoAdded:
            return "Auto"
        case .manualAdded:
            return "Manual"
        }
    }
}

struct ObservedVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var normalizedText: String
    var count: Int
    var lastSeenAt: Date
    var confidence: DictionaryVariantConfidence

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String,
        count: Int = 1,
        lastSeenAt: Date = Date(),
        confidence: DictionaryVariantConfidence
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
        self.count = count
        self.lastSeenAt = lastSeenAt
        self.confidence = confidence
    }
}

struct DictionaryReplacementTerm: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var normalizedText: String

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
    }
}

struct DictionaryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var groupID: UUID?
    var groupNameSnapshot: String?
    var source: DictionaryEntrySource
    var createdAt: Date
    var updatedAt: Date
    var lastMatchedAt: Date?
    var matchCount: Int
    var status: DictionaryEntryStatus
    var observedVariants: [ObservedVariant]
    var replacementTerms: [DictionaryReplacementTerm]

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case normalizedTerm
        case groupID
        case groupNameSnapshot
        case source
        case createdAt
        case updatedAt
        case lastMatchedAt
        case matchCount
        case status
        case observedVariants
        case replacementTerms
    }

    init(
        id: UUID = UUID(),
        term: String,
        normalizedTerm: String,
        groupID: UUID? = nil,
        groupNameSnapshot: String? = nil,
        source: DictionaryEntrySource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMatchedAt: Date? = nil,
        matchCount: Int = 0,
        status: DictionaryEntryStatus = .active,
        observedVariants: [ObservedVariant] = [],
        replacementTerms: [DictionaryReplacementTerm] = []
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.groupID = groupID
        self.groupNameSnapshot = groupNameSnapshot
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMatchedAt = lastMatchedAt
        self.matchCount = matchCount
        self.status = status
        self.observedVariants = observedVariants
        self.replacementTerms = replacementTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        normalizedTerm = try container.decode(String.self, forKey: .normalizedTerm)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        groupNameSnapshot = try container.decodeIfPresent(String.self, forKey: .groupNameSnapshot)
        source = try container.decode(DictionaryEntrySource.self, forKey: .source)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastMatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0
        status = try container.decodeIfPresent(DictionaryEntryStatus.self, forKey: .status) ?? .active
        observedVariants = try container.decodeIfPresent([ObservedVariant].self, forKey: .observedVariants) ?? []
        replacementTerms = try container.decodeIfPresent([DictionaryReplacementTerm].self, forKey: .replacementTerms) ?? []
    }

    var matchKeys: [String] {
        [normalizedTerm] + replacementTerms.map(\.normalizedText)
    }

    func visibleMatchKeys(blockedKeys: Set<String>) -> [String] {
        if groupID == nil {
            return matchKeys.filter { !blockedKeys.contains($0) }
        }
        return matchKeys
    }
}

enum DictionaryMatchSource: String, Hashable {
    case term
    case replacementTerm
    case observedVariant
}

enum DictionaryMatchReason: String, Codable {
    case exactTerm
    case exactVariant
    case exactWindow
    case fuzzyWindow
}

struct DictionaryMatchCandidate: Identifiable, Hashable {
    let entryID: UUID
    let term: String
    let matchedText: String
    let normalizedMatchedText: String
    let score: Double
    let reason: DictionaryMatchReason
    let source: DictionaryMatchSource
    let matchRange: NSRange?

    nonisolated var id: String {
        let location = matchRange?.location ?? -1
        let length = matchRange?.length ?? 0
        return "\(entryID.uuidString)|\(normalizedMatchedText)|\(reason.rawValue)|\(source.rawValue)|\(location)|\(length)"
    }

    nonisolated var allowsAutomaticReplacement: Bool {
        if source == .replacementTerm {
            return true
        }

        switch reason {
        case .exactVariant:
            return true
        case .exactWindow:
            return score >= 0.985
        case .fuzzyWindow:
            return score >= 0.97 && normalizedMatchedText.count >= 5
        case .exactTerm:
            return false
        }
    }

    nonisolated var shouldPersistObservedVariant: Bool {
        source != .replacementTerm && reason != .exactTerm
    }
}

struct DictionaryPromptContext {
    let entries: [DictionaryEntry]
    let candidates: [DictionaryMatchCandidate]

    var isEmpty: Bool {
        entries.isEmpty || candidates.isEmpty
    }

    func glossaryText(limit: Int = 12) -> String {
        guard !isEmpty else { return "" }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var lines: [String] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let entry = entriesByID[candidate.entryID] else { continue }
            guard seen.insert(entry.id).inserted else { continue }
            lines.append("- \(entry.term)")
            if lines.count >= limit {
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    func glossaryText(for purpose: DictionaryGlossaryPurpose) -> String {
        glossaryText(policy: purpose.selectionPolicy)
    }

    func glossaryText(policy: DictionaryGlossarySelectionPolicy) -> String {
        guard !isEmpty, policy.maxTerms > 0, policy.maxCharacters > 0 else { return "" }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var lines: [String] = []
        var characterCount = 0

        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let entry = entriesByID[candidate.entryID] else { continue }
            guard seen.insert(entry.id).inserted else { continue }

            let line = "- \(entry.term)"
            let separatorCost = lines.isEmpty ? 0 : 1
            let nextCharacterCount = characterCount + separatorCost + line.count

            if !lines.isEmpty && nextCharacterCount > policy.maxCharacters {
                break
            }
            if lines.isEmpty && line.count > policy.maxCharacters {
                lines.append(line)
                break
            }

            lines.append(line)
            characterCount = nextCharacterCount

            if lines.count >= policy.maxTerms {
                break
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct DictionaryCorrectionResult {
    let text: String
    let candidates: [DictionaryMatchCandidate]
    let correctedTerms: [String]
    let correctionSnapshots: [DictionaryCorrectionSnapshot]
}

struct DictionaryCorrectionSnapshot: Codable, Hashable {
    let originalText: String
    let correctedText: String
    let finalLocation: Int
    let finalLength: Int
}

struct DictionaryImportResult: Equatable {
    let addedCount: Int
    let skippedCount: Int
}

enum DictionaryStoreError: LocalizedError {
    case emptyTerm
    case duplicateTerm
    case replacementMatchesDictionaryTerm
    case duplicateReplacementTerm(String)

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return AppLocalization.localizedString("Dictionary term cannot be empty.")
        case .duplicateTerm:
            return AppLocalization.localizedString("This term already exists in the dictionary.")
        case .replacementMatchesDictionaryTerm:
            return AppLocalization.localizedString("Replacement match term cannot be the same as the dictionary term.")
        case .duplicateReplacementTerm(let term):
            return AppLocalization.format(
                "This replacement match term already exists in the dictionary: %@.",
                term
            )
        }
    }
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var reloadGeneration = 0
    private var filteredEntriesCache: [DictionaryFilter: [DictionaryEntry]] = [:]
    private var validationIndex = DictionaryValidationIndex(entries: [])
    private let persistenceEnabled: Bool
    private let repository: DictionaryRepositoryProtocol?

    convenience init() {
        self.init(defaults: .standard, fileManager: .default)
    }

    init(
        defaults: UserDefaults,
        fileManager: FileManager,
        initialEntries: [DictionaryEntry]? = nil,
        persistenceEnabled: Bool = true,
        repository: DictionaryRepositoryProtocol? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.persistenceEnabled = persistenceEnabled
        self.repository = persistenceEnabled ? (repository ?? DictionaryRepository()) : repository
        if let initialEntries {
            applyReloadedEntries(initialEntries)
        } else {
            reload()
        }
    }

    func reload() {
        do {
            if let repository {
                let decoded = try repository.allEntries()
                if !decoded.isEmpty || !legacyDictionaryFileExists() {
                    applyReloadedEntries(decoded)
                    return
                }
            }

            let url = try dictionaryFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                applyReloadedEntries([])
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            applyReloadedEntries(decoded)
        } catch {
            applyReloadedEntries([])
        }
    }

    func reloadAsync() {
        reloadGeneration += 1
        let generation = reloadGeneration

        let repository = repository
        let url: URL?
        do {
            url = try dictionaryFileURL()
        } catch {
            applyReloadedEntries([])
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, url] in
            let decodedEntries: [DictionaryEntry]
            if let repository,
               let repositoryEntries = try? repository.allEntries(),
               !repositoryEntries.isEmpty || url.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true {
                decodedEntries = repositoryEntries
            } else if let url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    decodedEntries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
                } catch {
                    decodedEntries = []
                }
            } else {
                decodedEntries = []
            }

            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.applyReloadedEntries(decodedEntries)
            }
        }
    }

    func filteredEntries(for filter: DictionaryFilter) -> [DictionaryEntry] {
        filteredEntriesCache[filter] ?? entries
    }

    func entries(
        filter: DictionaryFilter,
        query: String = "",
        limit: Int,
        offset: Int
    ) -> [DictionaryEntry] {
        if let repository,
           let pagedEntries = try? repository.entries(
            filter: filter,
            query: query,
            limit: limit,
            offset: offset
           ) {
            return pagedEntries
        }

        let filteredEntries = filteredEntries(for: filter)
        let searchedEntries = DictionaryEntryCollection.searchEntries(filteredEntries, query: query)
        guard offset < searchedEntries.count else { return [] }
        return Array(searchedEntries.dropFirst(offset).prefix(limit))
    }

    func entryCount(filter: DictionaryFilter, query: String = "") -> Int {
        if let repository,
           let count = try? repository.entryCount(filter: filter, query: query) {
            return count
        }
        return DictionaryEntryCollection.searchEntries(filteredEntries(for: filter), query: query).count
    }

    func loadEntries(
        filter: DictionaryFilter,
        query: String = "",
        limit: Int,
        offset: Int,
        completion: @escaping (Int, [DictionaryEntry]) -> Void
    ) {
        guard let repository else {
            let searchedEntries = DictionaryEntryCollection.searchEntries(filteredEntries(for: filter), query: query)
            let page = offset < searchedEntries.count
                ? Array(searchedEntries.dropFirst(offset).prefix(limit))
                : []
            completion(searchedEntries.count, page)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let count = (try? repository.entryCount(filter: filter, query: query)) ?? 0
            let page = (try? repository.entries(filter: filter, query: query, limit: limit, offset: offset)) ?? []
            DispatchQueue.main.async {
                completion(count, page)
            }
        }
    }

    func allTerms(limit: Int? = nil) -> [String] {
        if let repository,
           let terms = try? repository.allTerms(limit: limit) {
            return terms
        }
        if let limit {
            return Array(entries.map(\.term).prefix(limit))
        }
        return entries.map(\.term)
    }

    func promptBiasTermsText(
        activeGroupID: UUID?,
        maxCount: Int = 24,
        maxCharacters: Int = 320
    ) -> String {
        DictionaryEntryCollection.promptBiasTermsText(
            from: entries,
            activeGroupID: activeGroupID,
            maxCount: maxCount,
            maxCharacters: maxCharacters
        )
    }

    func createManualEntry(
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        try createEntry(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .manual
        )
    }

    func createAutoEntry(
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        try createEntry(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .auto
        )
    }

    private func createEntry(
        term: String,
        replacementTerms: [String],
        groupID: UUID?,
        groupNameSnapshot: String?,
        source: DictionaryEntrySource
    ) throws {
        let prepared = try prepareEntryInput(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID
        )
        let now = Date()
        let entry = DictionaryEntry(
            term: prepared.display,
            normalizedTerm: prepared.normalized,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: source,
            createdAt: now,
            updatedAt: now,
            replacementTerms: prepared.replacementTerms
        )
        var updatedEntries = entries
        updatedEntries.insert(entry, at: 0)
        try upsertPersistedEntry(entry)
        replaceEntries(updatedEntries)
    }

    func updateEntry(
        id: UUID,
        term: String,
        replacementTerms: [String] = [],
        groupID: UUID?,
        groupNameSnapshot: String?
    ) throws {
        let prepared = try prepareEntryInput(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            excluding: id
        )
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updatedEntry = entries[index]
        updatedEntry.term = prepared.display
        updatedEntry.normalizedTerm = prepared.normalized
        updatedEntry.groupID = groupID
        updatedEntry.groupNameSnapshot = groupNameSnapshot
        updatedEntry.replacementTerms = prepared.replacementTerms
        updatedEntry.updatedAt = Date()

        let reservedKeys = Set([prepared.normalized] + prepared.replacementTerms.map(\.normalizedText))
        updatedEntry.observedVariants.removeAll { reservedKeys.contains($0.normalizedText) }
        try upsertPersistedEntry(updatedEntry)

        var updatedEntries = entries
        updatedEntries[index] = updatedEntry
        replaceEntries(updatedEntries)
    }

    func delete(id: UUID) {
        guard deletePersistedEntry(id: id) else { return }
        replaceEntries(entries.filter { $0.id != id }, sort: false)
    }

    func clearAll() {
        guard clearPersistedEntries() else { return }
        replaceEntries([], sort: false)
    }

    func exportTransferJSONString() throws -> String {
        try DictionaryTransferManager.exportJSONString(entries: entries)
    }

    func importTransferJSONString(_ json: String) throws -> DictionaryImportResult {
        let payload = try DictionaryTransferManager.importPayload(from: json)
        return importTransferEntries(payload.entries)
    }

    func makeMatcherIfEnabled(activeGroupID: UUID?) -> DictionaryMatcher? {
        let configuration = matcherConfiguration(for: activeGroupID)
        guard !configuration.entries.isEmpty else { return nil }
        return DictionaryMatcher(
            entries: configuration.entries,
            blockedGlobalMatchKeys: configuration.blockedGlobalMatchKeys
        )
    }

    func makeMatcherIfEnabled(for text: String, activeGroupID: UUID?) -> DictionaryMatcher? {
        let configuration = matcherConfiguration(for: activeGroupID, sourceText: text)
        guard !configuration.entries.isEmpty else { return nil }
        return DictionaryMatcher(
            entries: configuration.entries,
            blockedGlobalMatchKeys: configuration.blockedGlobalMatchKeys
        )
    }

    func correctionContext(for text: String, activeGroupID: UUID?) -> DictionaryCorrectionResult? {
        guard let matcher = makeMatcherIfEnabled(for: text, activeGroupID: activeGroupID) else { return nil }
        return matcher.applyCorrections(
            to: text,
            automaticReplacementEnabled: defaults.bool(forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled)
        )
    }

    func matchContext(for text: String, activeGroupID: UUID?) -> DictionaryCorrectionResult? {
        guard let matcher = makeMatcherIfEnabled(for: text, activeGroupID: activeGroupID) else { return nil }
        let candidates = matcher.recallCandidates(in: text)
        guard !candidates.isEmpty else { return nil }
        return DictionaryCorrectionResult(
            text: text,
            candidates: candidates,
            correctedTerms: [],
            correctionSnapshots: []
        )
    }

    func glossaryContext(for text: String, activeGroupID: UUID?) -> DictionaryPromptContext? {
        guard let matcher = makeMatcherIfEnabled(for: text, activeGroupID: activeGroupID) else { return nil }
        let context = matcher.promptContext(for: text)
        return context.isEmpty ? nil : context
    }

    func hasEntry(normalizedTerm: String, activeGroupID: UUID?) -> Bool {
        let normalized = normalizedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if let repository,
           let hasEntry = try? repository.hasEntry(normalizedTerm: normalized, activeGroupID: activeGroupID) {
            return hasEntry
        }

        let configuration = matcherConfiguration(for: activeGroupID)
        return configuration.entries.contains { entry in
            entry.visibleMatchKeys(blockedKeys: configuration.blockedGlobalMatchKeys).contains(normalized)
        }
    }

    func activeEntriesForRemoteRequest(activeGroupID: UUID?) -> [DictionaryEntry] {
        DictionaryEntryCollection.activeEntriesForRemoteRequest(from: entries, activeGroupID: activeGroupID)
    }

    func activeEntriesAcrossAllScopesForRemoteSync() -> [DictionaryEntry] {
        return entries.filter { $0.status == .active }
    }

    func recordMatches(_ candidates: [DictionaryMatchCandidate]) {
        let updatedEntries = recordCandidates(candidates)
        guard !candidates.isEmpty else { return }
        replaceEntries(entries)
        persistEntries(updatedEntries)
    }

    nonisolated static func normalizeTerm(_ input: String) -> String {
        DictionaryTermNormalizer.normalize(input)
    }

    private func matcherConfiguration(for activeGroupID: UUID?) -> (entries: [DictionaryEntry], blockedGlobalMatchKeys: Set<String>) {
        (
            entries: DictionaryEntryCollection.activeEntriesForRemoteRequest(
                from: entries,
                activeGroupID: activeGroupID
            ),
            blockedGlobalMatchKeys: DictionaryEntryCollection.blockedGlobalMatchKeys(
                from: entries,
                activeGroupID: activeGroupID
            )
        )
    }

    private func matcherConfiguration(
        for activeGroupID: UUID?,
        sourceText: String
    ) -> (entries: [DictionaryEntry], blockedGlobalMatchKeys: Set<String>) {
        if let repository,
           let candidates = try? repository.matchingEntries(
               sourceText: sourceText,
               activeGroupID: activeGroupID,
               limit: 200
           ) {
            return DictionaryEntryCollection.matcherConfiguration(
                for: candidates,
                activeGroupID: activeGroupID
            )
        }
        return matcherConfiguration(for: activeGroupID)
    }

    private func prepareEntryInput(
        term: String,
        replacementTerms: [String],
        groupID: UUID?,
        excluding excludedID: UUID? = nil,
        existingEntries: [DictionaryEntry]? = nil,
        validationIndex providedValidationIndex: DictionaryValidationIndex? = nil
    ) throws -> DictionaryPreparedEntryInput {
        let resolvedEntries: [DictionaryEntry]?
        if providedValidationIndex == nil, existingEntries == nil, excludedID != nil {
            resolvedEntries = entries
        } else {
            resolvedEntries = existingEntries
        }

        let resolvedValidationIndex = providedValidationIndex
            ?? (resolvedEntries == nil ? validationIndex : nil)

        return try DictionaryEntryInputPreparer.prepare(
            term: term,
            replacementTerms: replacementTerms,
            groupID: groupID,
            excluding: excludedID,
            entries: resolvedEntries,
            validationIndex: resolvedValidationIndex
        )
    }

    private func importTransferEntries(_ transferEntries: [DictionaryTransferManager.Entry]) -> DictionaryImportResult {
        var mergedEntries = entries
        var importValidationIndex = validationIndex
        var addedCount = 0
        var skippedCount = 0

        for transferEntry in transferEntries {
            do {
                let prepared = try prepareEntryInput(
                    term: transferEntry.term,
                    replacementTerms: transferEntry.replacementTerms,
                    groupID: transferEntry.groupID,
                    validationIndex: importValidationIndex
                )
                let now = Date()
                let entry = DictionaryEntry(
                    term: prepared.display,
                    normalizedTerm: prepared.normalized,
                    groupID: transferEntry.groupID,
                    groupNameSnapshot: transferEntry.groupNameSnapshot,
                    source: .manual,
                    createdAt: now,
                    updatedAt: now,
                    replacementTerms: prepared.replacementTerms
                )
                mergedEntries.append(entry)
                importValidationIndex.insert(entry)
                addedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        replaceEntries(mergedEntries)
        persist()
        return DictionaryImportResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    private func recordCandidates(_ candidates: [DictionaryMatchCandidate]) -> [DictionaryEntry] {
        guard !candidates.isEmpty else { return [] }
        let now = Date()
        let grouped = Dictionary(grouping: candidates, by: \.entryID)
        var updatedEntries: [DictionaryEntry] = []

        for (entryID, matches) in grouped {
            guard let index = entries.firstIndex(where: { $0.id == entryID }) else { continue }
            entries[index].lastMatchedAt = now
            entries[index].matchCount += matches.count
            entries[index].updatedAt = now

            for candidate in matches where candidate.shouldPersistObservedVariant {
                let normalizedReservedKeys = Set(
                    [entries[index].normalizedTerm] + entries[index].replacementTerms.map(\.normalizedText)
                )
                guard !normalizedReservedKeys.contains(candidate.normalizedMatchedText) else { continue }
                upsertVariant(
                    into: &entries[index],
                    text: candidate.matchedText,
                    normalizedText: candidate.normalizedMatchedText,
                    confidence: confidence(for: candidate)
                )
            }
            updatedEntries.append(entries[index])
        }

        return updatedEntries
    }

    private func upsertVariant(
        into entry: inout DictionaryEntry,
        text: String,
        normalizedText: String,
        confidence: DictionaryVariantConfidence
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let variantIndex = entry.observedVariants.firstIndex(where: { $0.normalizedText == normalizedText }) {
            entry.observedVariants[variantIndex].count += 1
            entry.observedVariants[variantIndex].lastSeenAt = Date()
            entry.observedVariants[variantIndex].confidence = higherConfidence(
                lhs: entry.observedVariants[variantIndex].confidence,
                rhs: confidence
            )
        } else {
            entry.observedVariants.append(
                ObservedVariant(
                    text: text,
                    normalizedText: normalizedText,
                    confidence: confidence
                )
            )
            entry.observedVariants.sort { $0.count > $1.count }
        }
    }

    private func confidence(for candidate: DictionaryMatchCandidate) -> DictionaryVariantConfidence {
        if candidate.score >= 0.985 {
            return .high
        }
        if candidate.score >= 0.92 {
            return .medium
        }
        return .low
    }

    private func higherConfidence(lhs: DictionaryVariantConfidence, rhs: DictionaryVariantConfidence) -> DictionaryVariantConfidence {
        let rank: [DictionaryVariantConfidence: Int] = [
            .low: 0,
            .medium: 1,
            .high: 2
        ]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private func persist() {
        guard persistenceEnabled, let repository else { return }
        do {
            try repository.replaceAll(entries)
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func persistEntry(_ entry: DictionaryEntry) {
        do {
            try upsertPersistedEntry(entry)
        } catch {
            persist()
        }
    }

    private func upsertPersistedEntry(_ entry: DictionaryEntry) throws {
        guard persistenceEnabled, let repository else { return }
        try repository.upsert(entry)
    }

    private func persistEntries(_ updatedEntries: [DictionaryEntry]) {
        guard persistenceEnabled, let repository else { return }
        do {
            for entry in updatedEntries {
                try repository.upsert(entry)
            }
        } catch {
            persist()
        }
    }

    private func deletePersistedEntry(id: UUID) -> Bool {
        guard persistenceEnabled, let repository else { return true }
        do {
            try repository.delete(id: id)
            return true
        } catch {
            return false
        }
    }

    private func clearPersistedEntries() -> Bool {
        guard persistenceEnabled, let repository else { return true }
        do {
            try repository.clearAll()
            return true
        } catch {
            return false
        }
    }

    private func legacyDictionaryFileExists() -> Bool {
        (try? dictionaryFileURL()).map { fileManager.fileExists(atPath: $0.path) } ?? false
    }

    private func dictionaryFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    private func sortEntries(_ values: [DictionaryEntry]) -> [DictionaryEntry] {
        DictionaryEntryCollection.sortedEntries(values)
    }

    private func applyReloadedEntries(_ decodedEntries: [DictionaryEntry]) {
        replaceEntries(decodedEntries)
    }

    private func replaceEntries(_ values: [DictionaryEntry], sort: Bool = true) {
        let resolvedEntries = sort ? sortEntries(values) : values
        entries = resolvedEntries
        filteredEntriesCache = DictionaryEntryCollection.filteredEntriesCache(for: resolvedEntries)
        validationIndex = DictionaryValidationIndex(entries: resolvedEntries)
    }
}
