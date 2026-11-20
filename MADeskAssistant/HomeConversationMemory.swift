//
//  HomeConversationMemory.swift
//  MADeskAssistant
//
//  Classifies one chat turn before any record is opened or saved.
//  The model may draft a reply. This type does not write a case, a task, or a setting.
//

import Foundation
import Observation

enum HomeReplyStyle: String {
    case usual
    case brief
    case detailed
}

enum HomeTurnIntent: Equatable {
    case reviseLastReply
    case needsEarlierReply
    case setStyle(HomeReplyStyle)
    case reopenCase(String)
}

enum HomeTurnRouter {
    static func interpret(_ input: String, hasEarlierReply: Bool) -> HomeTurnIntent? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        if let style = styleChange(in: original) {
            return .setStyle(style)
        }
        if let hint = caseHint(from: original) {
            return .reopenCase(hint)
        }
        if wantsRevision(original) {
            return hasEarlierReply ? .reviseLastReply : .needsEarlierReply
        }
        return nil
    }

    static func isCaseResume(_ input: String) -> Bool {
        caseHint(from: input) != nil
    }

    /// Words used to find a saved case. Empty means the case already open.
    static func hintTokens(_ hint: String) -> [String] {
        var seen = Set<String>()
        return normalize(hint).split(separator: " ").map(String.init).filter { token in
            token.count >= 2 && !hintStop.contains(token) && seen.insert(token).inserted
        }
    }

    static func matchesCase(tokens: [String], title: String, identifier: String) -> Bool {
        guard !tokens.isEmpty else { return false }
        let haystack = Set(normalize(title + " " + identifier).split(separator: " ").map(String.init))
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// True when a sentence should be answered in conversation instead of the desk command list.
    /// Exact utilities such as timers, tasks, and "help" stay commands.
    static func talksRatherThanCommands(_ command: String) -> Bool {
        let text = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.contains("joke") || text.contains("timer") { return false }
        if text.contains("wake") || text.contains("sleep") || text.contains("quiet") || text.contains("mute") {
            return false
        }
        if text.contains("what time") || text == "time" || text.contains("tell time") { return false }
        if text == "help" || text == "commands" || text == "what can you do" || text == "show commands" {
            return false
        }
        if text.contains("calendar") || text.contains("news") { return false }
        if text.contains("medicine") || text.contains("medication") || text.contains("dosage")
            || text.contains("dose") || text.contains("prescription") {
            return false
        }
        if text.contains("water") && (text.contains("plant") || text.contains("pothos") || text.contains("snake plant")) {
            return false
        }
        let taskCommand = [
            "add task", "add a task", "new task", "create task", "create a task",
            "make task", "make a task", "remember to", "remind me to",
            "please add task", "please add a task"
        ].contains { text.hasPrefix($0) }
        if taskCommand || text.contains("complete task") || text.contains("finish task")
            || text.contains("show tasks") || text.contains("my tasks") || text.contains("show task list")
            || text.contains("my cases") || text.contains("list cases") {
            return false
        }
        if text.contains("?") {
            let followUp = ["explain", "simpler", "simply", "shorter", "mean", "help me", "why ", "how ", "that"]
                .contains { text.contains($0) }
            if followUp { return true }
            let exactRecall = text.contains("diagnosis") || text.contains("assessment")
                || text.contains("plan") || text.contains("treatment")
                || text.contains("summarize") || text.contains("summary")
                || text.contains("my cases") || text.contains("list cases")
            if exactRecall { return false }
            return true
        }
        let cues = [
            "explain", "wait", "help me", "can you", "could you", "would you",
            "let's", "lets ", "make it", "make that", "go back", "back to",
            "what about", "why ", "how ", "simpler", "simply", "shorter",
            "rephrase", "elaborate", "i meant", "plain english"
        ]
        return cues.contains { text.hasPrefix($0) || text.contains($0) }
    }

    /// A whole message that only asks to wipe the reply and start again.
    static func isFreshPrompt(_ input: String) -> Bool {
        let text = normalize(input)
        if text == "cancel" || text == "cancel timer" { return false }
        return freshPrompts.contains(text)
    }

    private static let freshPrompts: Set<String> = [
        "clear", "clear screen", "clear the screen", "clear this", "clear chat",
        "new prompt", "start over", "start again", "never mind", "nevermind",
        "forget it", "scratch that"
    ]

    static func styleChange(in input: String) -> HomeReplyStyle? {
        var text = normalize(input)
        var trimmedLead = true
        while trimmedLead {
            trimmedLead = false
            for lead in politeness where text.hasPrefix(lead) {
                text = String(text.dropFirst(lead.count))
                trimmedLead = true
            }
        }
        if text.hasSuffix(" please") {
            text.removeLast(" please".count)
        }
        let count = text.split(separator: " ").count
        guard count > 0, count <= 18 else { return nil }
        if text.contains("cpt") || text.contains("icd") { return nil }

        if matchesPhrase(text, phrases: usualPhrases) { return .usual }
        if matchesPhrase(text, phrases: briefPhrases) { return .brief }
        if matchesPhrase(text, phrases: detailedPhrases) { return .detailed }
        return nil
    }

    private static func matchesPhrase(_ text: String, phrases: [String]) -> Bool {
        let tails = ["", " for now", " for this chat", " from now on", " unless i ask", " unless i ask for details"]
        return phrases.contains { phrase in
            tails.contains { text == phrase + $0 }
        }
    }

    static func caseHint(from input: String) -> String? {
        let text = normalize(input)
        guard let prefix = resumePrefixes.first(where: { text.hasPrefix($0) }) else { return nil }
        var hint = String(text.dropFirst(prefix.count))
        for trail in [" we discussed", " we talked about", " again", " please"] where hint.hasSuffix(trail) {
            hint.removeLast(trail.count)
        }
        hint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        for trail in [" case", " note", " chart"] where hint.hasSuffix(trail) {
            hint.removeLast(trail.count)
        }
        hint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if blockedCaseHints.contains(hint) { return nil }
        if hint.hasPrefix("cpt") || hint.hasPrefix("icd") || hint.hasPrefix("task") { return nil }
        return hint
    }

    static func wantsRevision(_ input: String) -> Bool {
        let text = normalize(input)
        let count = text.split(separator: " ").count
        guard count > 0, count <= 18 else { return false }
        if text.contains(" cpt") || text.hasPrefix("cpt") || text.contains(" icd") || text.hasPrefix("icd") {
            return false
        }
        if text.hasPrefix("add ") || text.hasPrefix("remove ") || text.hasPrefix("start ") {
            return false
        }
        if revisionExact.contains(text) { return true }
        if text.contains(" note") || text.hasPrefix("note") || text.contains(" case") || text.hasPrefix("case") || text.contains("chart") {
            return false
        }
        let aboutPrior = text.contains("that") || text.contains(" it") || text.hasPrefix("it ")
            || text.contains("again") || text.contains("this")
        if !aboutPrior {
            let namesTopic = ["plan", "hpi", "ros", "exam", "assessment", "diagnosis", "note", "case", "task"]
                .contains { text.contains($0) }
            if namesTopic { return false }
        }
        if revisionCues.contains(where: { text.contains($0) }) { return true }
        return count <= 4 && (text.contains("shorter") || text.contains("simpler") || text.contains("rephrase"))
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let politeness = [
        "please ", "can you ", "could you ", "would you ",
        "i want you to ", "i d like you to ", "i would like you to "
    ]

    private static let briefPhrases = [
        "keep your answers short unless i ask for details",
        "keep your answers short unless i ask",
        "keep answers short unless i ask for details",
        "keep your answers short",
        "keep your replies short",
        "keep answers short",
        "keep replies short",
        "keep answers shorter",
        "keep it short",
        "keep them short",
        "be brief",
        "be more brief",
        "short answers",
        "shorter answers",
        "less detail",
        "use short answers"
    ]

    private static let detailedPhrases = [
        "be more detailed",
        "give me more detail",
        "more detail",
        "longer answers",
        "add more detail",
        "you can elaborate",
        "be detailed"
    ]

    private static let usualPhrases = [
        "normal answers",
        "go back to normal",
        "regular answers",
        "usual answers",
        "default answers",
        "stop being brief",
        "normal length"
    ]

    private static let resumePrefixes = [
        "go back to ", "back to ", "return to ", "switch back to ", "switch to ",
        "pull up ", "reopen ", "open ", "take me back to ",
        "lets go back to ", "let s go back to "
    ]

    private static let blockedCaseHints: Set<String> = [
        "", "a", "a note", "note", "a new note", "new note", "a practice note",
        "practice note", "a soap note", "soap note", "a new practice note",
        "a practice", "practice", "new practice", "a new practice", "a soap", "soap", "a new", "new"
    ]

    private static let hintStop: Set<String> = [
        "the", "a", "an", "my", "our", "that", "this", "same", "one", "case", "note",
        "chart", "please", "fictional", "practice", "saved", "old", "previous", "to",
        "and", "or", "with", "but"
    ]

    private static let revisionExact: Set<String> = [
        "wait", "again", "shorter", "simpler", "continue", "huh", "go on"
    ]

    private static let revisionCues = [
        "explain that", "explain it", "explain this", "more simply", "simpler",
        "plain english", "plain language", "make it shorter", "make that shorter",
        "make this shorter", "too long", "say that again", "repeat that",
        "what did you mean", "what do you mean", "keep going", "elaborate",
        "expand on that", "the second one", "the first one", "the third one",
        "that one", "the other one", "what about that", "in other words", "simplify that",
        "simplify it", "simplify this", "rephrase", "try again", "say it again",
        "one more time", "too wordy"
    ]
}

@MainActor
@Observable
final class HomeConversationMemory {
    private(set) var style: HomeReplyStyle = .usual
    private(set) var awaitingNote = false
    private(set) var lastUser = ""
    private(set) var lastAssistant = ""

    var hasEarlierReply: Bool {
        !lastAssistant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func interpret(_ input: String) -> HomeTurnIntent? {
        HomeTurnRouter.interpret(input, hasEarlierReply: hasEarlierReply)
    }

    func use(_ newStyle: HomeReplyStyle) {
        style = newStyle
    }

    func expectNote() {
        awaitingNote = true
    }

    func finishNoteIntake() {
        awaitingNote = false
    }

    func remember(user: String, assistant: String) {
        let userText = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = assistant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !assistantText.isEmpty else { return }
        lastUser = String(userText.prefix(500))
        lastAssistant = String(assistantText.prefix(1_500))
    }

    func reset() {
        lastUser = ""
        lastAssistant = ""
        style = .usual
        awaitingNote = false
    }
}
