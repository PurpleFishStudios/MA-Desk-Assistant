import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HomeCaseConversation {
    private enum Section {
        case hpi, ros, pe, assessment, plan, reason, soap
    }

    private(set) var currentTitle: String?
    private var currentID: PersistentIdentifier?
    private var pendingIDs: [PersistentIdentifier] = []
    private var pendingSection: Section?
    private var ownerID: String?

    var currentCaseID: PersistentIdentifier? { currentID }

    func reset() {
        currentTitle = nil
        currentID = nil
        pendingIDs = []
        pendingSection = nil
        ownerID = nil
    }

    func adopt(_ item: PracticeCase, profileID: String) {
        ownerID = normalized(profileID)
        currentID = item.persistentModelID
        currentTitle = "\(value(item.title)) · \(value(item.identifier))"
        pendingIDs = []
        pendingSection = nil
    }

    func currentCaseWasRemoved(from cases: [PracticeCase]) -> Bool {
        guard let currentID else { return false }
        return !cases.contains { $0.persistentModelID == currentID }
    }

    // Returns nil for inputs that should go to the existing command handler.
    func handle(_ input: String, cases: [PracticeCase], profileID: String) -> String? {
        let owner = normalized(profileID)
        if ownerID != owner {
            reset()
            ownerID = owner
        }
        let available = cases.filter {
            guard let id = $0.ownerProfileID else { return false }
            return normalized(id) == owner && !owner.isEmpty
        }
        if let currentID, !available.contains(where: { $0.persistentModelID == currentID }) {
            self.currentID = nil
            currentTitle = nil
        }

        let query = normalized(input)
        let words = tokens(query)
        guard !words.isEmpty else { return nil }

        if ["forget case", "clear case", "clear current case", "deselect case"].contains(query) {
            reset()
            ownerID = owner
            return "Current case cleared."
        }
        if ["list cases", "list my cases", "show my cases", "my cases"].contains(query) {
            return choose(from: available, section: nil)
        }

        if !pendingIDs.isEmpty {
            let pending = pendingIDs.compactMap { id in
                available.first { $0.persistentModelID == id }
            }
            let selection = selectionNumber(query)
            if let selection {
                guard selection > 0, selection <= pending.count else {
                    return "Choose a number from 1 to \(pending.count), or type the case title or identifier."
                }
                let section = pendingSection
                return select(pending[selection - 1], section: section)
            }
            let exact = exactMatches(query, cases: pending)
            if exact.count == 1 {
                return select(exact[0], section: requestedSection(query) ?? pendingSection)
            }
            if ["cancel", "never mind", "nevermind"].contains(query) {
                pendingIDs = []
                pendingSection = nil
                return "Case selection canceled."
            }
        }

        let section = requestedSection(query)
        let hasCaseWord = !words.isDisjoint(with: ["case", "cases", "note", "notes", "chart"])
        let hasRecallWord = !words.isDisjoint(with: ["saved", "documented", "wrote", "write", "said", "entered", "recorded"])
        let sectionOnly = ["hpi", "ros", "pe", "assessment", "plan", "physical exam", "what is the plan", "what was the plan", "what about the plan", "and the plan", "what about the hpi"].contains(query)
        let exact = exactMatches(query, cases: available)
        let namedSection = section != nil && !exact.isEmpty
        guard hasCaseWord || hasRecallWord && section != nil || sectionOnly || namedSection else {
            pendingIDs = []
            pendingSection = nil
            return nil
        }

        // Never silently interpret an explicit unknown case name as the current case.
        let nameWords = words.subtracting(stopWords)
        let hasName = !nameWords.isEmpty
        var matches: [PracticeCase] = []
        if !exact.isEmpty {
            matches = exact
        } else if hasName {
            matches = available.filter { item in
                let candidate = tokens(item.title + " " + item.identifier)
                return nameWords.isSubset(of: candidate)
            }
        }

        if hasName || !exact.isEmpty {
            if matches.isEmpty {
                pendingIDs = []
                pendingSection = nil
                if isQuestion(query) { return nil }
                return "No matching fictional case was found in this profile. Try its saved title or fake identifier, or type ‘list cases’. No other case was substituted."
            }
            if matches.count == 1 {
                return select(matches[0], section: section)
            }
            return choose(from: matches, section: section)
        }

        let explicitlyLatest = words.contains("latest") || words.contains("last") || words.contains("recent")
        if explicitlyLatest, let latest = available.first {
            return select(latest, section: section)
        }
        if let currentID, let item = available.first(where: { $0.persistentModelID == currentID }) {
            return select(item, section: section)
        }
        return choose(from: available, section: section)
    }

    private func choose(from items: [PracticeCase], section: Section?) -> String {
        pendingIDs = items.map(\.persistentModelID)
        pendingSection = section
        guard !items.isEmpty else {
            return "No matching owned fictional cases are available in this profile."
        }
        let list = items.enumerated().map { index, item in
            "\(index + 1). \(value(item.title)) · \(value(item.identifier))"
        }.joined(separator: "\n")
        return "Which fictional case do you mean?\n\n\(list)\n\nReply with its number, saved title, or identifier."
    }

    private func select(_ item: PracticeCase, section: Section?) -> String {
        currentID = item.persistentModelID
        currentTitle = "\(value(item.title)) · \(value(item.identifier))"
        pendingIDs = []
        pendingSection = nil
        guard let section else {
            return "Current case: \(currentTitle ?? "")\n\nAsk ‘What did I write in the HPI?’, ‘What was the plan?’, or ‘Show the saved SOAP text’."
        }
        let heading: String
        let text: String
        switch section {
        case .hpi: heading = "HPI"; text = value(item.hpi)
        case .ros: heading = "ROS"; text = value(item.ros)
        case .pe: heading = "Physical examination"; text = value(item.pe)
        case .assessment: heading = "Assessment"; text = value(item.assessment)
        case .plan: heading = "Plan"; text = value(item.plan)
        case .reason: heading = "Reason for visit"; text = value(item.reasonForVisit)
        case .soap:
            heading = "Saved SOAP fields"
            text = [("Reason for visit", item.reasonForVisit), ("HPI", item.hpi),
                    ("ROS", item.ros), ("PE", item.pe), ("Assessment", item.assessment),
                    ("Plan", item.plan)].map { "\($0.0):\n\(value($0.1))" }.joined(separator: "\n\n")
        }
        return "Saved \(heading) for ‘\(value(item.title))’:\n\n\(text)\n\nSource: \(value(item.title)) · \(value(item.identifier)) → \(heading)\nSaved: \(item.updatedAt.formatted())\nExact saved-text recall — not an AI interpretation or a new clinical recommendation."
    }

    private func isQuestion(_ query: String) -> Bool {
        query.contains("?") || query.hasPrefix("what") || query.hasPrefix("why") || query.hasPrefix("how") || query.hasPrefix("which")
    }

    private func requestedSection(_ query: String) -> Section? {
        let w = tokens(query)
        if w.contains("hpi") || query.contains("history of present illness") { return .hpi }
        if w.contains("ros") || query.contains("review of systems") { return .ros }
        if w.contains("pe") || query.contains("physical exam") || query.contains("examination") { return .pe }
        if !w.isDisjoint(with: ["assessment", "diagnosis", "diagnoses"]) { return .assessment }
        if !w.isDisjoint(with: ["plan", "treatment"]) { return .plan }
        if query.contains("reason for visit") || query.contains("chief complaint") { return .reason }
        if !w.isDisjoint(with: ["soap", "summary", "summarize", "overview"]) { return .soap }
        return nil
    }

    private func exactMatches(_ query: String, cases: [PracticeCase]) -> [PracticeCase] {
        cases.filter { item in
            let title = normalized(item.title)
            let identifier = normalized(item.identifier)
            return (!title.isEmpty && (" " + query + " ").contains(" " + title + " ")) ||
                (!identifier.isEmpty && (" " + query + " ").contains(" " + identifier + " "))
        }
    }

    private func selectionNumber(_ query: String) -> Int? {
        let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5]
        let cleaned = query.replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: " one", with: "")
            .replacingOccurrences(of: "number ", with: "")
        return Int(cleaned) ?? ordinals[cleaned]
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func tokens(_ text: String) -> Set<String> {
        Set(normalized(text).split(separator: " ").map(String.init))
    }
    private func value(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not entered" : text
    }
    private let stopWords: Set<String> = [
        "hey", "hi", "hello", "please", "can", "could", "would", "you", "i", "me", "my", "we", "our",
        "look", "at", "up", "find", "open", "select", "choose", "tell", "show", "get", "read", "recall", "about",
        "the", "a", "an", "and", "or", "in", "on", "of", "for", "from", "to", "with", "it", "its", "s",
        "what", "did", "do", "does", "was", "were", "is", "are", "have", "has", "had", "that", "this", "said",
        "write", "wrote", "entered", "recorded", "document", "documented", "saved", "previous", "earlier",
        "case", "cases", "note", "notes", "chart", "fictional", "practice", "patient",
        "hpi", "history", "present", "illness", "ros", "review", "systems", "pe", "physical", "exam", "examination",
        "assessment", "diagnosis", "diagnoses", "plan", "treatment", "reason", "visit", "chief", "complaint",
        "soap", "text", "summary", "summarize", "overview", "last", "latest", "recent", "one"
    ]
}
