import Foundation

struct DictionaryHistoryScanModelOption: Identifiable, Hashable {
    enum Source: Hashable {
        case local
        case remote
    }

    let id: String
    let source: Source
    let title: String
    let detail: String
}

struct DictionaryHistoryScanRequest: Hashable {
    let modelOptionID: String
    let filterSettings: DictionarySuggestionFilterSettings
}

private enum DictionaryHistoryScanParseError {
    static let domain = "Voxt.DictionaryHistoryScan"

    static func invalidText(code: Int) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: AppLocalization.localizedString("Dictionary ingestion returned invalid text.")
            ]
        )
    }
}

enum DictionaryHistoryScanResponseParser {
    static func parseTerms(from rawResponse: String) throws -> [String] {
        let normalizedResponse = CustomLLMOutputSanitizer.normalizeResultText(rawResponse)
        guard !normalizedResponse.isEmpty else {
            throw DictionaryHistoryScanParseError.invalidText(code: -11)
        }

        if let terms = try parseExactJSONArrayTerms(from: normalizedResponse) {
            return normalizeAcceptedTerms(from: terms)
        }

        if let extractedJSONArray = extractJSONArrayString(from: normalizedResponse),
           let terms = try parseExactJSONArrayTerms(from: extractedJSONArray) {
            return normalizeAcceptedTerms(from: terms)
        }

        VoxtLog.warning(
            "Dictionary history scan returned invalid JSON array. preview=\(responsePreview(normalizedResponse))"
        )
        throw DictionaryHistoryScanParseError.invalidText(code: -13)
    }

    static func normalizeAcceptedTerms(from terms: [String]) -> [String] {
        var seen = Set<String>()
        var orderedTerms: [String] = []

        for term in terms {
            let normalized = DictionaryStore.normalizeTerm(term)
            guard !normalized.isEmpty else { continue }
            guard DictionaryHistoryScanCandidateValidator.shouldAccept(term: term) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            orderedTerms.append(term)
        }

        return orderedTerms
    }

    static func responsesTextFormatPayload() -> [String: Any] {
        [
            "format": [
                "type": "json_schema",
                "name": "dictionary_history_terms",
                "strict": true,
                "schema": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "term": [
                                "type": "string"
                            ]
                        ],
                        "required": ["term"]
                    ]
                ]
            ]
        ]
    }

    static func extractJSONArrayString(from text: String) -> String? {
        let characters = Array(text)
        var startIndex: Int?
        var bracketDepth = 0
        var isInsideString = false
        var isEscaping = false

        for (index, character) in characters.enumerated() {
            if isInsideString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "[" {
                if bracketDepth == 0 {
                    startIndex = index
                }
                bracketDepth += 1
                continue
            }

            if character == "]", bracketDepth > 0 {
                bracketDepth -= 1
                if bracketDepth == 0, let startIndex {
                    return String(characters[startIndex...index])
                }
            }
        }

        return nil
    }

    private static func parseExactJSONArrayTerms(from text: String) throws -> [String]? {
        guard let data = text.data(using: .utf8) else {
            throw DictionaryHistoryScanParseError.invalidText(code: -12)
        }
        do {
            guard let rawItems = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }

            var parsedTerms: [String] = []
            parsedTerms.reserveCapacity(rawItems.count)

            for item in rawItems {
                guard item.count == 1, let rawTerm = item["term"] as? String else {
                    return nil
                }
                let trimmed = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw DictionaryHistoryScanParseError.invalidText(code: -10)
                }
                parsedTerms.append(trimmed)
            }

            return parsedTerms
        } catch {
            return nil
        }
    }

    private static func responsePreview(_ text: String) -> String {
        let collapsedWhitespace = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return String(collapsedWhitespace.prefix(300))
    }
}

struct DictionaryHistoryScanPromptRecord: Encodable {
    let id: String
    let kind: String
    let groupName: String?
    let text: String
    let dictionaryHitTerms: [String]
    let dictionaryCorrectedTerms: [String]
}

enum DictionaryHistoryScanSupport {
    static func buildPrompt(
        for batch: [TranscriptionHistoryEntry],
        filterSettings: DictionarySuggestionFilterSettings,
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup],
        userMainLanguage: String,
        userOtherLanguages: String
    ) throws -> String {
        let records = batch.map { entry in
            let scope = resolvedHistoryScope(
                for: entry,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
            return DictionaryHistoryScanPromptRecord(
                id: entry.id.uuidString,
                kind: entry.kind.rawValue,
                groupName: scope.groupName,
                text: trimmedHistoryScanText(entry.text),
                dictionaryHitTerms: entry.dictionaryHitTerms,
                dictionaryCorrectedTerms: entry.dictionaryCorrectedTerms
            )
        }

        let recordsXML = historyScanXMLRecords(from: records)
        let settings = filterSettings.sanitized()
        return resolvedPrompt(
            template: settings.prompt,
            userMainLanguage: userMainLanguage,
            userOtherLanguages: userOtherLanguages,
            historyRecordsXML: recordsXML
        )
    }

    static func parseCandidates(
        terms: [String],
        batch: [TranscriptionHistoryEntry],
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) throws -> [DictionaryHistoryScanCandidate] {
        guard !terms.isEmpty else { return [] }
        var candidatesByKey: [String: DictionaryHistoryScanCandidate] = [:]

        for term in terms {
            let sourceEntries = resolvedSourceEntries(for: term, in: batch)
            let scopedEntries = sourceEntries.isEmpty ? batch : sourceEntries

            let scope = resolvedCandidateScope(
                sourceEntries: scopedEntries,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
            let evidenceSample = resolvedEvidenceSample(
                preferredSample: nil,
                term: term,
                sourceEntries: scopedEntries
            )
            guard DictionaryHistoryScanCandidateValidator.shouldAccept(
                term: term,
                evidenceSample: evidenceSample
            ) else {
                continue
            }
            let key = "\(DictionaryStore.normalizeTerm(term))|\(scope.groupID?.uuidString ?? "global")"
            let historyEntryIDs = scopedEntries.map(\.id)

            if let existing = candidatesByKey[key] {
                let mergedIDs = Array(Set(existing.historyEntryIDs + historyEntryIDs)).sorted {
                    $0.uuidString < $1.uuidString
                }
                candidatesByKey[key] = DictionaryHistoryScanCandidate(
                    term: existing.term.count >= term.count ? existing.term : term,
                    historyEntryIDs: mergedIDs,
                    groupID: existing.groupID,
                    groupNameSnapshot: existing.groupNameSnapshot ?? scope.groupName,
                    evidenceSample: existing.evidenceSample.isEmpty ? evidenceSample : existing.evidenceSample
                )
            } else {
                candidatesByKey[key] = DictionaryHistoryScanCandidate(
                    term: term,
                    historyEntryIDs: historyEntryIDs,
                    groupID: scope.groupID,
                    groupNameSnapshot: scope.groupName,
                    evidenceSample: evidenceSample
                )
            }
        }

        return candidatesByKey.values.sorted {
            $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
    }

    static func loadGroups(defaults: UserDefaults = .standard) -> [AppBranchGroup] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            return []
        }
        return groups
    }

    private static func resolvedPrompt(
        template: String,
        userMainLanguage: String,
        userOtherLanguages: String,
        historyRecordsXML: String
    ) -> String {
        var prompt = template.trimmingCharacters(in: .whitespacesAndNewlines)

        if prompt.contains("{{USER_MAIN_LANGUAGE}}") {
            prompt = prompt.replacingOccurrences(of: "{{USER_MAIN_LANGUAGE}}", with: userMainLanguage)
        } else {
            prompt += "\n\nUser’s main language: \(userMainLanguage)"
        }

        if prompt.contains("{{USER_OTHER_LANGUAGES}}") {
            prompt = prompt.replacingOccurrences(of: "{{USER_OTHER_LANGUAGES}}", with: userOtherLanguages)
        } else {
            prompt += "\n\nOther frequently used languages: \(userOtherLanguages)"
        }

        if prompt.contains("{{HISTORY_RECORDS}}") {
            prompt = prompt.replacingOccurrences(of: "{{HISTORY_RECORDS}}", with: historyRecordsXML)
        } else {
            prompt += "\n\nHistory records:\n\(historyRecordsXML)"
        }

        return prompt
    }

    private static func historyScanXMLRecords(
        from records: [DictionaryHistoryScanPromptRecord]
    ) -> String {
        let body = records.map { record in
            let groupName = record.groupName.map { xmlEscapedText($0) } ?? ""
            let dictionaryHitTerms = record.dictionaryHitTerms
                .map { "<term>\(xmlEscapedText($0))</term>" }
                .joined()
            let dictionaryCorrectedTerms = record.dictionaryCorrectedTerms
                .map { "<term>\(xmlEscapedText($0))</term>" }
                .joined()

            return """
            <historyRecord id="\(xmlEscapedAttribute(record.id))" kind="\(xmlEscapedAttribute(record.kind))">
              <groupName>\(groupName)</groupName>
              <text>\(xmlEscapedText(record.text))</text>
              <dictionaryHitTerms>\(dictionaryHitTerms)</dictionaryHitTerms>
              <dictionaryCorrectedTerms>\(dictionaryCorrectedTerms)</dictionaryCorrectedTerms>
            </historyRecord>
            """
        }.joined(separator: "\n")

        return "<historyRecords>\n\(body)\n</historyRecords>"
    }

    private static func resolvedSourceEntries(
        for term: String,
        in batch: [TranscriptionHistoryEntry]
    ) -> [TranscriptionHistoryEntry] {
        batch.filter {
            $0.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func resolvedCandidateScope(
        sourceEntries: [TranscriptionHistoryEntry],
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) -> (groupID: UUID?, groupName: String?) {
        let scopes = sourceEntries.map {
            resolvedHistoryScope(
                for: $0,
                groupsByID: groupsByID,
                groupsByLowercasedName: groupsByLowercasedName
            )
        }
        let uniqueScopedIDs = Array(Set(scopes.compactMap(\.groupID)))
        guard uniqueScopedIDs.count == 1, scopes.allSatisfy({ $0.groupID == uniqueScopedIDs[0] }) else {
            return (nil, nil)
        }
        return (uniqueScopedIDs[0], scopes.first?.groupName)
    }

    private static func resolvedHistoryScope(
        for entry: TranscriptionHistoryEntry,
        groupsByID: [UUID: AppBranchGroup],
        groupsByLowercasedName: [String: AppBranchGroup]
    ) -> (groupID: UUID?, groupName: String?) {
        if let matchedGroupID = entry.matchedGroupID {
            let groupName = groupsByID[matchedGroupID]?.name
                ?? entry.matchedAppGroupName
                ?? entry.matchedURLGroupName
            return (matchedGroupID, groupName)
        }

        if let groupName = (entry.matchedAppGroupName ?? entry.matchedURLGroupName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !groupName.isEmpty,
           let group = groupsByLowercasedName[groupName.lowercased()] {
            return (group.id, group.name)
        }

        return (nil, nil)
    }

    private static func resolvedEvidenceSample(
        preferredSample: String?,
        term: String,
        sourceEntries: [TranscriptionHistoryEntry]
    ) -> String {
        let trimmedPreferred = preferredSample?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPreferred.isEmpty {
            return String(trimmedPreferred.prefix(80))
        }
        guard let firstEntry = sourceEntries.first else { return "" }
        return historyEvidenceSample(for: term, in: firstEntry.text)
    }

    private static func historyEvidenceSample(for term: String, in text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        guard let range = trimmedText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(trimmedText.prefix(80))
        }

        let start = trimmedText.distance(from: trimmedText.startIndex, to: range.lowerBound)
        let lowerOffset = max(0, start - 18)
        let upperOffset = min(trimmedText.count, start + term.count + 18)
        let lowerIndex = trimmedText.index(trimmedText.startIndex, offsetBy: lowerOffset)
        let upperIndex = trimmedText.index(trimmedText.startIndex, offsetBy: upperOffset)
        let snippet = trimmedText[lowerIndex..<upperIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(snippet.prefix(80))
    }

    private static func trimmedHistoryScanText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 320 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 320)
        return String(trimmed[..<index])
    }

    private static func xmlEscapedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlEscapedAttribute(_ text: String) -> String {
        xmlEscapedText(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
