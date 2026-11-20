//
//  PracticeNoteChatDraft.swift
//  MADeskAssistant
//
//  Turns a chat sentence into an editable fictional practice note.
//  The ROS and physical exam are an original general-adult teaching
//  template. They are not copied from an EHR macro, and they are not
//  an observed exam or a finished clinical note.
//

import Foundation

enum PracticeNoteSection: Equatable {
    case ros
    case pe
}

struct StatedCPT: Equatable {
    var code: String
    var description: String
}

enum PracticeNoteChatAction: Equatable {
    case start(PracticeNoteNarrative)
    case removeFinding(PracticeNoteSection, String)
    case addFinding(PracticeNoteSection, String)
    case addICD(String)
    case removeICD(String)
    case addCPT(StatedCPT)
    case removeCPT(String)
    case explainCPT
    case explainICD
}

struct PracticeNoteNarrative: Equatable {
    var ageYears: Int?
    var sex: String?
    var history: String
    var concern: String
    var request: String
    var statedExam: String
    var statedCPT: StatedCPT?
    var raw: String

    var codingTerms: [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for source in [concern, history] {
            for term in Self.codingTerms(in: source) where seen.insert(term.lowercased()).inserted {
                terms.append(term)
                if terms.count == 3 { return terms }
            }
        }
        return terms
    }

    fileprivate static func codingTerms(in text: String) -> [String] {
        let pieces = text
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " but ", with: ",", options: .caseInsensitive)
            .split(whereSeparator: { ",;/".contains($0) })
            .map { String($0) }

        let skip: Set<String> = [
            "etc", "unspecified", "unknown", "none", "na", "n/a", "patient", "pt",
            "mild", "severe", "acute", "chronic", "left", "right", "bilateral",
            "a", "an", "the", "with", "of", "and", "or", "this", "that", "these",
            "those", "something", "anything"
        ]
        var terms: [String] = []
        for piece in pieces {
            let lowered = " \(piece.lowercased()) "
            if lowered.contains(" no ") || lowered.contains(" denies ") || lowered.contains(" without ") {
                continue
            }
            var cleaned = piece.lowercased()
            cleaned = cleaned.replacingOccurrences(
                of: #"\b(for|over|since|x)\b.*$"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"\b\d+\s*(day|days|week|weeks|month|months|year|years|hour|hours)\b"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard cleaned.count >= 3, cleaned.count <= 60, !skip.contains(cleaned) else { continue }
            terms.append(cleaned)
        }
        return terms
    }
}

struct PracticeNoteFields: Equatable {
    var title: String
    var reasonForVisit: String
    var hpi: String
    var ros: String
    var pe: String
    var assessment: String
    var plan: String
}

enum PracticeNoteChatRouter {
    static let cptHelp = """
    CPT is the procedure and visit-code set used on a practice note. This assistant does not choose an E/M level.

    Office-visit families to review, not to copy as a final answer:
    • New patient: 99202–99205
    • Established patient: 99212–99215
    The level depends on new versus established status and on documented decision making or time.

    To put a code on the current fictional note, type the code yourself. Example: “Add CPT 99213 established office visit”. Remove it with “Remove CPT 99213”.
    """

    static let icdHelp = """
    ICD-10-CM is the diagnosis-code reference. A search result is not a final code.

    Ask a lookup question, for example “What is the code for cough?”
    To attach a reference to the current fictional note, say “Add ICD cough” or “Add ICD R05.9”.
    Remove one with “Remove ICD R05.9”.
    Codes that need more characters are not attached.
    """

    static func action(for input: String) -> PracticeNoteChatAction? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        let lowered = original.lowercased()
        guard lowered.count == original.count else { return nil }
        let text = stripLead(lowered)
        let source = String(original.dropFirst(lowered.count - text.count))

        if let remainder = remainder(after: startPrefixes, in: text, source: source) {
            return .start(narrative(from: remainder))
        }
        if let code = firstCapture(#"^(?:please\s+)?(?:remove|delete)\s+(?:the\s+)?cpt(?:\s+code)?\s+#?([0-9]{5})\b"#, in: text), !code.isEmpty {
            return .removeCPT(code)
        }
        if let stated = statedCPT(in: text, pattern: #"^(?:please\s+)?(?:add|attach)\s+(?:a\s+)?cpt(?:\s+code)?\s+#?([0-9]{5})(?:[- ]([0-9]{2}))?(?:\s*[-—:]\s*|\s+)?(.*)$"#) {
            return .addCPT(stated)
        }
        if text.range(of: #"^(?:please\s+)?(?:add|attach)\s+(?:a\s+)?cpt\b"#, options: .regularExpression) != nil {
            return .explainCPT
        }
        if let code = firstCapture(
            #"^(?:please\s+)?(?:remove|delete)\s+(?:the\s+)?icd[- ]?10(?:-cm)?(?:\s+code)?\s+([a-z][0-9][0-9a-z.]*)"#,
            in: text
        ) {
            return .removeICD(code.uppercased())
        }
        if let term = firstCapture(
            #"^(?:please\s+)?(?:add|attach)\s+(?:an?\s+)?icd[- ]?10(?:-cm)?(?:\s+code)?\s*(?:for\s+)?(.+)$"#,
            in: text,
            source: source
        ) {
            let cleaned = term
                .replacingOccurrences(of: #"\s+to\s+(?:the\s+)?(?:note|case|chart)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if cleaned.isEmpty || cleaned == "code" || cleaned == "a code" {
                return .explainICD
            }
            return .addICD(cleaned)
        }
        if text.range(of: #"^(?:please\s+)?(?:add|attach)\s+(?:an?\s+)?icd[- ]?10\b"#, options: .regularExpression) != nil {
            return .explainICD
        }
        if let edit = findingEdit(text, source: source) {
            return edit
        }
        if text.contains("cpt"), text.hasPrefix("what") || text.hasPrefix("explain") || text.contains("what is") || text.contains("what's") {
            return .explainCPT
        }
        if text.range(of: #"^what(?:'s| is| does)\s+icd[- ]?10(?:-cm)?\b"#, options: .regularExpression) != nil,
           !text.contains(" for ") {
            return .explainICD
        }
        return nil
    }

    static func narrative(from remainder: String) -> PracticeNoteNarrative {
        let original = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = original.lowercased()
        var history = ""
        var concern = ""
        var request = ""
        var statedExam = ""

        let markers = markerRanges(in: lowered)
        if markers.isEmpty {
            concern = trimClause(original)
        } else {
            for index in markers.indices {
                let start = markers[index].valueStart
                let end = index + 1 < markers.count ? markers[index + 1].markerStart : lowered.endIndex
                guard start <= end else { continue }
                let slice = trimClause(String(original[start..<end]))
                switch markers[index].kind {
                case .history: history = slice
                case .concern: concern = slice
                case .request: request = slice
                case .exam: statedExam = slice
                }
            }
            if concern.isEmpty && history.isEmpty && request.isEmpty && statedExam.isEmpty {
                concern = trimClause(original)
            }
        }

        return PracticeNoteNarrative(
            ageYears: age(in: lowered),
            sex: sex(in: lowered),
            history: history,
            concern: concern,
            request: request,
            statedExam: statedExam,
            statedCPT: statedCPT(in: original, pattern: #"(?i)\bcpt(?:\s+code)?\s*#?\s*([0-9]{5})(?:[- ]([0-9]{2}))?(?:\s*[-—:]\s*|\s+)?([a-z][^.,;\n]{0,80})?"#),
            raw: original
        )
    }

    private static let startPrefixes = [
        "start a soap note",
        "start soap note",
        "start a practice note",
        "start practice note",
        "start a new note",
        "draft a soap note",
        "draft a practice note",
        "draft a note",
        "start a note",
        "start note",
        "new soap note",
        "new practice note",
        "begin a note",
        "begin note",
        "open a practice note",
        "start a not"
    ]

    private enum MarkerKind {
        case history, concern, request, exam
    }

    private struct Marker {
        var kind: MarkerKind
        var markerStart: String.Index
        var valueStart: String.Index
    }

    private static func markerRanges(in lowered: String) -> [Marker] {
        let patterns: [(String, MarkerKind)] = [
            (#"(?<![a-z])history of\b"#, .history),
            (#"(?<![a-z])h/o\b"#, .history),
            (#"(?<![a-z])hx of\b"#, .history),
            (#"(?<![a-z])hx\b"#, .history),
            (#"(?<![a-z])pmh\b"#, .history),
            (#"(?<![a-z])complaining of\b"#, .concern),
            (#"(?<![a-z])complains of\b"#, .concern),
            (#"(?<![a-z])complaint of\b"#, .concern),
            (#"(?<![a-z])chief complaint\b"#, .concern),
            (#"(?<![a-z])c/o\b"#, .concern),
            (#"(?<![a-z])here for\b"#, .request),
            (#"(?<![a-z])would like\b"#, .request),
            (#"(?<![a-z])requesting\b"#, .request),
            (#"(?<![a-z])requests\b"#, .request),
            (#"(?<![a-z])wants\b"#, .request),
            (#"(?<![a-z])on exam\b"#, .exam),
            (#"(?<![a-z])exam shows\b"#, .exam),
            (#"(?<![a-z])physical exam\b"#, .exam),
            (#"(?<![a-z])exam:"#, .exam),
            (#"(?<![a-z])pe:"#, .exam)
        ]
        var found: [Marker] = []
        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            regex.enumerateMatches(in: lowered, range: range) { match, _, _ in
                guard let match, let hit = Range(match.range, in: lowered) else { return }
                found.append(Marker(kind: kind, markerStart: hit.lowerBound, valueStart: hit.upperBound))
            }
        }
        found.sort { $0.markerStart < $1.markerStart }
        var kept: [Marker] = []
        var cursor = lowered.startIndex
        for marker in found where marker.markerStart >= cursor {
            kept.append(marker)
            cursor = marker.valueStart
        }
        return kept
    }

    private static func stripLead(_ text: String) -> String {
        var value = text
        let leads = ["hey ", "hi ", "ok ", "okay ", "please ", "can you ", "could you ", "would you "]
        var didStrip = true
        while didStrip {
            didStrip = false
            for lead in leads where value.hasPrefix(lead) {
                value.removeFirst(lead.count)
                didStrip = true
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remainder(after prefixes: [String], in text: String, source: String) -> String? {
        for prefix in prefixes where text.hasPrefix(prefix) {
            let rest = text.dropFirst(prefix.count)
            if prefix == "start a not", let next = rest.first, next.isLetter {
                continue
            }
            var slice = String(source.dropFirst(prefix.count))
            slice = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            if slice.hasPrefix(",") || slice.hasPrefix(":") || slice.hasPrefix("-") {
                slice = String(slice.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return slice
        }
        return nil
    }

    private static func findingEdit(_ text: String, source: String) -> PracticeNoteChatAction? {
        let remove = #"^(?:please\s+)?(?:remove|take out|delete|clear)\s+(.+?)\s+from\s+(?:the\s+)?(ros|review of systems|pe|physical exam|physical examination)$"#
        if let pair = phraseAndSection(remove, text: text, source: source) {
            return .removeFinding(pair.1, pair.0)
        }
        let add = #"^(?:please\s+)?(?:add|put)\s+(.+?)\s+(?:to|in|into)\s+(?:the\s+)?(ros|review of systems|pe|physical exam|physical examination)$"#
        if let pair = phraseAndSection(add, text: text, source: source) {
            return .addFinding(pair.1, pair.0)
        }
        return nil
    }

    private static func phraseAndSection(_ pattern: String, text: String, source: String) -> (String, PracticeNoteSection)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let phraseRange = Range(match.range(at: 1), in: source),
              let sectionRange = Range(match.range(at: 2), in: text) else { return nil }
        var phrase = source[phraseRange].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if phrase.lowercased().hasPrefix("the ") { phrase = String(phrase.dropFirst(4)) }
        guard phrase.count >= 3 else { return nil }
        let section = text[sectionRange]
        if section == "ros" || section == "review of systems" { return (phrase, .ros) }
        return (phrase, .pe)
    }

    private static func age(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*(?:year[- ]old|years[- ]old|yo|y/o|y\.o\.)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text),
              let years = Int(text[range]),
              (0...120).contains(years) else { return nil }
        return years
    }

    private static func sex(in text: String) -> String? {
        if text.range(of: #"\b(female|woman)\b"#, options: .regularExpression) != nil { return "female" }
        if text.range(of: #"\b(male|man)\b"#, options: .regularExpression) != nil { return "male" }
        return nil
    }

    private static func statedCPT(in text: String, pattern: String) -> StatedCPT? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let codeRange = Range(match.range(at: 1), in: text) else { return nil }
        var code = String(text[codeRange])
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound, let modifierRange = Range(match.range(at: 2), in: text) {
            let modifier = String(text[modifierRange])
            if !modifier.isEmpty { code += "-\(modifier)" }
        }
        let description: String
        if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound, let descriptionRange = Range(match.range(at: 3), in: text) {
            description = text[descriptionRange].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        } else {
            description = ""
        }
        return StatedCPT(code: code, description: description)
    }

    private static func trimClause(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:")))
        for prefix in ["and ", "with "] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        for suffix in [" and", " with"] where value.lowercased().hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:")))
    }

    private static func firstCapture(_ pattern: String, in text: String, source: String? = nil) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: source ?? text) else { return nil }
        return String((source ?? text)[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PracticeNoteTemplate {
    static func make(from narrative: PracticeNoteNarrative) -> PracticeNoteFields {
        let person = demographicLine(narrative)
        let history = narrative.history.isEmpty ? "Not stated." : narrative.history
        let concern = narrative.concern.isEmpty ? "Not stated." : narrative.concern
        let request = narrative.request.isEmpty ? "Not stated." : narrative.request
        var plan = """
        Draft for practice editing. This is not a treatment plan.
        Request stated in chat: \(request)

        \(CPTDraftText.initialBlock)
        """
        if let cpt = narrative.statedCPT {
            plan = CPTDraftText.add(cpt, to: plan).text
        }
        return PracticeNoteFields(
            title: title(for: narrative),
            reasonForVisit: narrative.concern.isEmpty ? "Not stated in chat." : clip(narrative.concern, 180),
            hpi: """
            Draft from chat. Keep only facts that belong in this fictional assignment.

            \(person)
            History: \(history)
            Concern: \(concern)
            """,
            ros: ros(for: narrative),
            pe: pe(for: narrative),
            assessment: """
            Draft for practice editing. This is not a diagnosis.

            Chat summary: \(person) History: \(history) Concern: \(concern) Request: \(request)

            Write the assessment you would submit. ICD-10-CM entries on this case are references for review, not a chosen diagnosis.
            """,
            plan: plan
        )
    }

    static func remove(phrase: String, from section: String) -> (text: String, removed: Bool) {
        let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 3 else { return (section, false) }
        var removed = false
        var output: [String] = []
        for line in section.components(separatedBy: "\n") {
            if isProtectedLine(line) {
                output.append(line)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                if line.lowercased().contains(needle) {
                    removed = true
                } else if !line.isEmpty {
                    output.append(line)
                }
                continue
            }
            let label = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if label.lowercased() == needle {
                removed = true
                continue
            }
            let clauses = rest.components(separatedBy: "; ")
            let kept = clauses.filter { clause in
                if clause.lowercased().contains(needle) {
                    removed = true
                    return false
                }
                return true
            }
            if !kept.isEmpty {
                output.append("\(label): \(kept.joined(separator: "; "))")
            }
        }
        return (output.joined(separator: "\n"), removed)
    }

    static func add(phrase: String, to section: String) -> String {
        let line = "Added in chat: \(phrase.trimmingCharacters(in: .whitespacesAndNewlines))"
        if section.localizedCaseInsensitiveContains(line) { return section }
        return section.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + line
    }

    private static func ros(for narrative: PracticeNoteNarrative) -> String {
        let source = narrative.concern.isEmpty ? narrative.raw : narrative.concern
        return PracticeTemplateStore.encoded(.ros, matching: source)
    }

    private static func pe(for narrative: PracticeNoteNarrative) -> String {
        return PracticeTemplateStore.encoded(.pe, matching: narrative.statedExam)
    }

    static func isAffirmed(_ triggers: [String], in text: String) -> Bool {
        let haystack = " \(text.lowercased()) "
        for trigger in triggers.sorted(by: { $0.count > $1.count }) {
            var search = haystack.startIndex
            let needle = trigger.lowercased()
            while let found = haystack.range(of: needle, range: search..<haystack.endIndex) {
                let beforeIsBoundary = found.lowerBound == haystack.startIndex || !haystack[haystack.index(before: found.lowerBound)].isLetter
                let afterIsBoundary = found.upperBound == haystack.endIndex || !haystack[found.upperBound].isLetter
                if beforeIsBoundary && afterIsBoundary && !isDenied(endingAt: found.lowerBound, in: haystack) {
                    return true
                }
                search = found.upperBound
            }
        }
        return false
    }

    private static func isDenied(endingAt index: String.Index, in text: String) -> Bool {
        let before = String(text[..<index])
        let sentence = before.components(separatedBy: CharacterSet(charactersIn: ".!?")).last ?? before
        let window: String
        if let contrast = sentence.range(of: " but ", options: .backwards) ?? sentence.range(of: " except ", options: .backwards) {
            window = " " + sentence[contrast.upperBound...] + " "
        } else {
            window = " " + sentence + " "
        }
        return [" no ", " denies ", " denied ", " without ", " negative "].contains { window.contains($0) }
    }

    private static func isProtectedLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("general adult") || lowered.hasPrefix("a negative") || lowered.hasPrefix("lines the chat")
    }

    private static func title(for narrative: PracticeNoteNarrative) -> String {
        let concern = clip(narrative.concern, 48)
        if let age = narrative.ageYears, !concern.isEmpty {
            return clip("\(age)-year-old — \(concern)", 80)
        }
        if !concern.isEmpty { return clip(concern, 80) }
        if let age = narrative.ageYears { return "\(age)-year-old practice note" }
        return "Practice note draft"
    }

    private static func demographicLine(_ narrative: PracticeNoteNarrative) -> String {
        switch (narrative.ageYears, narrative.sex) {
        case let (age?, sex?):
            return "\(age)-year-old \(sex) patient."
        case let (age?, nil):
            return "\(age)-year-old patient."
        case let (nil, sex?):
            return "\(sex.capitalized) patient. Age was not stated."
        case (nil, nil):
            return "Age and sex were not stated."
        }
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

enum CPTDraftText {
    static let header = "CPT drafts for review (not final billing codes):"
    static let footer = "End CPT drafts."

    static var initialBlock: String {
        """
        \(header)
        - None selected yet.
        - Review only, if this is an office visit: new patient 99202–99205, or established patient 99212–99215. The level depends on documented status, decision making, or time. No level was chosen.
        - Say “add CPT 99213 established office visit” to attach a code you want to review.
        \(footer)
        """
    }

    static func add(_ stated: StatedCPT, to plan: String) -> (text: String, added: Bool) {
        let code = stated.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.range(of: #"^[0-9]{5}(?:-[0-9]{2})?$"#, options: .regularExpression) != nil else {
            return (plan, false)
        }
        var lines = blockLines(in: plan)
        if lines.contains(where: { isCodeLine($0, code: code) }) {
            return (plan, false)
        }
        lines.removeAll { $0.localizedCaseInsensitiveContains("None selected yet") }
        let detail = stated.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = detail.isEmpty ? "entered in chat" : detail
        lines.append("- \(code) — \(suffix). Not a final billing code.")
        return (replacingBlock(with: lines, in: plan), true)
    }

    static func remove(code: String, from plan: String) -> (text: String, removed: Bool) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = blockLines(in: plan)
        let before = lines.count
        lines.removeAll { isCodeLine($0, code: cleanCode) }
        guard lines.count != before else { return (plan, false) }
        let hasCode = lines.contains { $0.range(of: #"^- [0-9]{5}\b"#, options: .regularExpression) != nil }
        if !hasCode && !lines.contains(where: { $0.localizedCaseInsensitiveContains("None selected yet") }) {
            lines.insert("- None selected yet.", at: 0)
        }
        return (replacingBlock(with: lines, in: plan), true)
    }

    private static func isCodeLine(_ line: String, code: String) -> Bool {
        line.range(of: "^- \(NSRegularExpression.escapedPattern(for: code))\\b", options: .regularExpression) != nil
    }

    private static func blockLines(in plan: String) -> [String] {
        guard let start = plan.range(of: header), let end = plan.range(of: footer), start.upperBound <= end.lowerBound else {
            return ["- None selected yet."]
        }
        return plan[start.upperBound..<end.lowerBound]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func replacingBlock(with lines: [String], in plan: String) -> String {
        let block = ([header] + lines + [footer]).joined(separator: "\n")
        guard let start = plan.range(of: header), let end = plan.range(of: footer), start.lowerBound <= end.upperBound else {
            return plan.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block
        }
        return plan.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
    }
}
