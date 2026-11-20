import Foundation
import ICD10CM

@MainActor
final class HomeICDLookup {
    private var store: ICD10Store?

    static func searchTerm(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("ai ") {
            text = String(text.dropFirst(3))
        }
        text = text.replacingOccurrences(of: "’", with: "'")
        let patterns = [
            #"^(?:hey[,\s]+)?(?:please\s+)?what(?:'s| is) the (?:icd[- ]?10(?:-cm)? )?codes? for\s*(.*)$"#,
            #"^(?:please\s+)?(?:find|search|look up|lookup)(?: the)? (?:icd[- ]?10(?:-cm)? )?codes?(?: for)?\s*(.*)$"#,
            #"^(?:icd[- ]?10(?:-cm)?)(?: codes?)?(?: for)?\s*(.*)$"#,
            #"^codes? for\s*(.*)$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let captured = Range(match.range(at: 1), in: text) else { continue }
            let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()[]{}?!.:,\"“”"))
            return String(text[captured]).trimmingCharacters(in: trim)
        }
        return nil
    }

    func search(_ term: String) async throws -> String {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return "Enter a condition or code. Example: What is the code for diabetes?"
        }
        guard term.count <= 250 else {
            return "Please enter a short documented condition or exact code, not a full patient note."
        }
        if store == nil { store = try ICD10Store() }
        guard let store else { return "The local ICD-10-CM database could not open." }
        try Task.checkCancellation()
        let hits = try await store.searchAsync(term, limit: 8, options: SearchOptions(useSynonyms: false))
        try Task.checkCancellation()
        guard !hits.isEmpty else {
            return "No local ICD-10-CM matches for ‘\(term)’. Try a more specific documented term or exact code.\n\nSource: Installed ICD10CM database. No AI code was substituted."
        }
        let rows = hits.enumerated().map { index, hit -> String in
            let flag: String
            if hit.code.requiresMoreCharacters || hit.isIncomplete {
                flag = "More specificity required"
            } else if hit.code.isBillable {
                flag = "Billable entry — coding review required"
            } else {
                flag = "Non-billable entry / category"
            }
            return "\(index + 1). \(hit.code.code) — \(hit.code.longDescription)\n   \(flag)"
        }.joined(separator: "\n\n")
        return """
        Local ICD-10-CM search: ‘\(term)’
        Showing \(hits.count) matching reference entries:

        \(rows)

        Search results are not a final code assignment. A broad term may need more documented detail. Review instructions and related notes in the ICD-10 Reference section before use.

        Source: Installed ICD10CM package database. Descriptions are returned directly from the package, not AI. This lookup does not attach codes or modify saved cases.
        """
    }

    /// First billable local match for a short term, or the exact code when `term` looks like one.
    /// Does not attach the code to a case.
    func referenceMatches(for term: String, limit: Int = 6) async throws -> ICDReferenceLookup {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return ICDReferenceLookup(matches: [], note: "Enter a condition or code.")
        }
        guard term.count <= 80 else {
            return ICDReferenceLookup(matches: [], note: "Use a short condition or an exact code, not a full note.")
        }
        if store == nil { store = try ICD10Store() }
        guard let store else {
            return ICDReferenceLookup(matches: [], note: "The local ICD-10-CM database could not open.")
        }

        let codeQuery = Self.looksLikeCode(term)
        let options = SearchOptions(
            useSynonyms: false,
            correctSpelling: !codeQuery,
            relaxedFallback: !codeQuery,
            cancelsPreviousSearches: true
        )
        let hits = try await store.searchAsync(term, limit: max(limit, 1), options: options)
        try Task.checkCancellation()

        if codeQuery {
            let wanted = Self.flatCode(term)
            if let exact = hits.first(where: { Self.flatCode($0.code.code) == wanted }) {
                if exact.code.isBillable && !exact.isIncomplete {
                    return ICDReferenceLookup(
                        matches: [ICDReferenceMatch(code: exact.code.code, descriptionText: exact.code.longDescription)],
                        note: nil
                    )
                }
                return ICDReferenceLookup(
                    matches: [],
                    note: "\(exact.code.code) needs a more specific code before it can be attached. \(exact.code.longDescription)"
                )
            }
            return ICDReferenceLookup(matches: [], note: "No local ICD-10-CM entry matched \(term). Nothing was attached.")
        }

        if let billable = hits.first(where: { $0.code.isBillable && !$0.isIncomplete }) {
            return ICDReferenceLookup(
                matches: [ICDReferenceMatch(code: billable.code.code, descriptionText: billable.code.longDescription)],
                note: nil
            )
        }
        return ICDReferenceLookup(
            matches: [],
            note: "No billable ICD-10-CM match for “\(term)”. Nothing was attached."
        )
    }

    func cancel() {
        store?.cancelInFlightSearches()
    }

    private static func looksLikeCode(_ term: String) -> Bool {
        term.range(of: #"^[A-Za-z]\d"#, options: .regularExpression) != nil
    }

    private static func flatCode(_ term: String) -> String {
        term.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
}

struct ICDReferenceMatch: Equatable {
    var code: String
    var descriptionText: String
}

struct ICDReferenceLookup: Equatable {
    var matches: [ICDReferenceMatch]
    var note: String?
}
