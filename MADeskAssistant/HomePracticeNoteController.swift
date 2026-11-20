//
//  HomePracticeNoteController.swift
//  MADeskAssistant
//
//  Saves chatbot practice-note drafts into the active profile's cases.
//

import Foundation
import SwiftData

@MainActor
enum HomePracticeNoteController {
    static func perform(
        _ action: PracticeNoteChatAction,
        profileID: String,
        profileName: String,
        cases: [PracticeCase],
        conversation: HomeCaseConversation,
        modelContext: ModelContext,
        lookup: HomeICDLookup
    ) async throws -> String {
        let owner = profileID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch action {
        case .start(let narrative):
            return try await start(
                narrative,
                owner: owner,
                profileName: profileName,
                conversation: conversation,
                modelContext: modelContext,
                lookup: lookup
            )
        case .addICD(let term):
            return try await addICD(
                term,
                cases: cases,
                conversation: conversation,
                modelContext: modelContext,
                lookup: lookup
            )
        case .explainCPT:
            return PracticeNoteChatRouter.cptHelp
        case .lookupCPT(let term):
            return PracticeCPTLibrary.lookupReply(for: term)
        case .explainICD:
            return PracticeNoteChatRouter.icdHelp
        case .removeFinding(let section, let phrase):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                let original = section == .ros ? item.ros : item.pe
                let result = PracticeTemplateStore.remove(phrase: phrase, from: original)
                    ?? PracticeNoteTemplate.remove(phrase: phrase, from: original)
                guard result.removed else {
                    return Change(
                        message: "“\(phrase)” was not found in the \(sectionName(section)). Nothing was changed.",
                        changed: false
                    )
                }
                if section == .ros { item.ros = result.text } else { item.pe = result.text }
                return Change(
                    message: "Removed “\(phrase)” from the \(sectionName(section)) on “\(item.title)”. Review it in Practice Cases before you submit.",
                    changed: true
                )
            }
        case .setFinding(let id, let detail):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                guard let finding = PracticeTemplateLibrary.finding(id: id) else {
                    return Change(message: "I could not match that to a ROS or exam button. Nothing was changed.", changed: false)
                }
                let original = finding.kind == .ros ? item.ros : item.pe
                let updated = PracticeTemplateStore.select(id: id, detail: detail, in: original)
                guard updated != original else {
                    return Change(message: "“\(finding.label)” is already selected on “\(item.title)”.", changed: false)
                }
                if finding.kind == .ros { item.ros = updated } else { item.pe = updated }
                let shown = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? finding.label
                    : "\(finding.label) (\(detail))"
                let place = finding.kind == .ros ? "ROS" : "physical exam"
                return Change(
                    message: "Selected “\(shown)” on the \(place) for “\(item.title)”. Open Practice Cases to see the button. This is a practice draft, not an observed exam.",
                    changed: true
                )
            }
        case .addFinding(let section, let phrase):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                let original = section == .ros ? item.ros : item.pe
                let kind: PracticeTemplateKind = section == .ros ? .ros : .pe
                let updated = PracticeTemplateStore.decode(original) == nil && !original.isEmpty
                    ? PracticeNoteTemplate.add(phrase: phrase, to: original)
                    : PracticeTemplateStore.add(phrase: phrase, to: original, kind: kind)
                guard updated != original else {
                    return Change(
                        message: "“\(phrase)” is already in the \(sectionName(section)) on “\(item.title)”.",
                        changed: false
                    )
                }
                if section == .ros { item.ros = updated } else { item.pe = updated }
                return Change(
                    message: "Selected “\(phrase)” on the \(sectionName(section)) for “\(item.title)”. Open Practice Cases to click more findings or add a site, such as R arm.",
                    changed: true
                )
            }
        case .removeICD(let code):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                guard let reference = item.codeReferences.first(where: {
                    $0.code.caseInsensitiveCompare(code) == .orderedSame
                }) else {
                    return Change(
                        message: "\(code) is not attached to “\(item.title)”. Nothing was changed.",
                        changed: false
                    )
                }
                let removedCode = reference.code
                modelContext.delete(reference)
                return Change(
                    message: "Removed ICD-10-CM reference \(removedCode) from “\(item.title)”. This does not change the written assessment.",
                    changed: true
                )
            }
        case .addCPT(let stated):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                let addedEntry = upsertCPT(stated, on: item)
                let result = CPTDraftText.add(stated, to: item.plan)
                guard addedEntry || result.added else {
                    return Change(
                        message: "CPT \(stated.code) was not added. It is already on “\(item.title)”, or it is not a 5-digit code. No final billing code was selected.",
                        changed: false
                    )
                }
                if result.added { item.plan = result.text }
                return Change(
                    message: "Added CPT \(stated.code) to “\(item.title)”. It is in the CPT section under the ICD-10-CM references. Link a diagnosis there before you submit. It is not a final billing code.",
                    changed: true
                )
            }
        case .removeCPT(let code):
            return edit(cases: cases, conversation: conversation, modelContext: modelContext) { item in
                var entries = PracticeCPTStore.load(item.cptDraftData)
                let before = entries.count
                entries.removeAll { $0.code == code }
                item.cptDraftData = PracticeCPTStore.save(entries)
                let result = CPTDraftText.remove(code: code, from: item.plan)
                guard entries.count != before || result.removed else {
                    return Change(
                        message: "CPT \(code) was not on “\(item.title)”. Nothing was changed.",
                        changed: false
                    )
                }
                if result.removed { item.plan = result.text }
                return Change(message: "Removed CPT \(code) from “\(item.title)”.", changed: true)
            }
        }
    }

    private struct Change {
        var message: String
        var changed: Bool
    }

    private static func start(
        _ narrative: PracticeNoteNarrative,
        owner: String,
        profileName: String,
        conversation: HomeCaseConversation,
        modelContext: ModelContext,
        lookup: HomeICDLookup
    ) async throws -> String {
        let fields = PracticeNoteTemplate.make(from: narrative)
        let attachment = try await references(for: narrative.codingTerms, lookup: lookup, exactCode: false)
        try Task.checkCancellation()

        let identifier = "CHAT-\(UUID().uuidString.prefix(8))"
        let item = PracticeCase(identifier: identifier, title: fields.title, ownerProfileID: owner)
        item.reasonForVisit = fields.reasonForVisit
        item.hpi = fields.hpi
        item.ros = fields.ros
        item.pe = fields.pe
        item.assessment = fields.assessment
        item.plan = fields.plan
        if let stated = narrative.statedCPT {
            _ = upsertCPT(stated, on: item)
        }
        item.updatedAt = .now
        modelContext.insert(item)
        for match in attachment.matches {
            item.codeReferences.append(
                PracticeCodeReference(code: match.code, descriptionText: match.descriptionText)
            )
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return "The practice note was not saved: \(error.localizedDescription)"
        }
        conversation.adopt(item, profileID: owner)

        let codeBlock: String
        if attachment.matches.isEmpty {
            codeBlock = attachment.note ?? "No ICD-10-CM reference was attached. You can say “Add ICD cough” or look one up with “What is the code for cough?”"
        } else {
            let rows = attachment.matches.map { "• \($0.code) — \($0.descriptionText)" }.joined(separator: "\n")
            codeBlock = """
            ICD-10-CM references attached for review, not as a final code:
            \(rows)
            \(attachment.note ?? "Confirm each code before you submit. Remove one with “Remove ICD \(attachment.matches[0].code)”.")
            """
        }
        let cptLine = narrative.statedCPT == nil
            ? "No CPT code was chosen. The plan lists office-visit ranges to review."
            : "CPT \(narrative.statedCPT?.code ?? "") was copied from the chat into the plan as a draft, not as a final billing code."
        return """
        Saved a fictional practice note for \(profileName).

        Case: \(item.title)
        Identifier: \(item.identifier)
        It is in Practice Cases for this profile. Edit it there, or keep editing it here. Export or submit it only after you review every line.

        ROS and physical exam buttons were preselected only for symptoms named in the chat. Open Practice Cases and click any other findings. The PDF lists the selected buttons, separated by semicolons.
        • “Remove cough from ROS”
        • “Add sore throat to ROS”
        • “Add wheezing to PE”
        • “Add ICD cough” or “Remove ICD R05.9”
        • “Add CPT 99213 established office visit” or “Remove CPT 99213”

        \(codeBlock)

        \(cptLine)

        ROS
        \(PracticeTemplateStore.exportText(from: item.ros).isEmpty ? "Nothing selected yet." : PracticeTemplateStore.exportText(from: item.ros))

        Physical exam
        \(PracticeTemplateStore.exportText(from: item.pe).isEmpty ? "Nothing selected yet. Click the exam findings in Practice Cases." : PracticeTemplateStore.exportText(from: item.pe))
        """
    }

    private static func addICD(
        _ term: String,
        cases: [PracticeCase],
        conversation: HomeCaseConversation,
        modelContext: ModelContext,
        lookup: HomeICDLookup
    ) async throws -> String {
        let exactCode = term.range(of: #"^[A-Za-z]\d"#, options: .regularExpression) != nil
        let attachment = try await references(for: [term], lookup: lookup, exactCode: exactCode)
        try Task.checkCancellation()
        guard let item = currentCase(in: cases, conversation: conversation) else {
            return """
            No note is open yet, so nothing was attached.

            \(formatted(attachment, term: term))

            Start a note, or select a saved case by its title. Then say “Add ICD \(term)” again if you want a reference on that draft.
            """
        }
        guard !attachment.matches.isEmpty else {
            return attachment.note ?? "No billable ICD-10-CM reference was found for “\(term)”. Nothing was attached."
        }
        var added: [ICDReferenceMatch] = []
        for match in attachment.matches where !item.codeReferences.contains(where: { $0.code == match.code }) {
            item.codeReferences.append(
                PracticeCodeReference(code: match.code, descriptionText: match.descriptionText)
            )
            added.append(match)
        }
        guard !added.isEmpty else {
            return "Those ICD-10-CM references were already on “\(item.title)”. Nothing new was attached.\n\n\(formatted(attachment, term: term))"
        }
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return "The ICD-10-CM reference was not saved: \(error.localizedDescription)"
        }
        let rows = added.map { "• \($0.code) — \($0.descriptionText)" }.joined(separator: "\n")
        return """
        Attached ICD-10-CM references to “\(item.title)” for review. They are not a final diagnosis code.

        \(rows)

        \(attachment.note ?? "")
        Remove one with “Remove ICD \(added[0].code)”.
        """
    }

    private static func edit(
        cases: [PracticeCase],
        conversation: HomeCaseConversation,
        modelContext: ModelContext,
        change: (PracticeCase) -> Change
    ) -> String {
        guard let item = currentCase(in: cases, conversation: conversation) else {
            return """
            No note is open yet, so I did not change one.
            Say “start a note”. I'll say when I'm ready, and the next message becomes the visit.
            """
        }
        let before = CaseEditHistory.Snapshot(item)
        let result = change(item)
        guard result.changed else { return result.message }
        CaseEditHistory.record(before)
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return "The edit was not saved: \(error.localizedDescription)"
        }
        return result.message
    }

enum CaseEditHistory {
    struct Snapshot {
        var id: PersistentIdentifier
        var ros: String
        var pe: String
        var plan: String
        var cpt: String

        init(_ item: PracticeCase) {
            id = item.persistentModelID
            ros = item.ros
            pe = item.pe
            plan = item.plan
            cpt = item.cptDraftData
        }

        func apply(to item: PracticeCase) {
            item.ros = ros
            item.pe = pe
            item.plan = plan
            item.cptDraftData = cpt
            item.updatedAt = .now
        }
    }

    private static var undoStack: [Snapshot] = []
    private static var redoStack: [Snapshot] = []

    static func record(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    static func undo(in cases: [PracticeCase], modelContext: ModelContext) -> String {
        step(from: &undoStack, to: &redoStack, in: cases, modelContext: modelContext, name: "Undo")
    }

    static func redo(in cases: [PracticeCase], modelContext: ModelContext) -> String {
        step(from: &redoStack, to: &undoStack, in: cases, modelContext: modelContext, name: "Redo")
    }

    private static func step(
        from source: inout [Snapshot],
        to destination: inout [Snapshot],
        in cases: [PracticeCase],
        modelContext: ModelContext,
        name: String
    ) -> String {
        guard let snapshot = source.popLast() else { return "Nothing to \(name.lowercased())." }
        guard let item = cases.first(where: { $0.persistentModelID == snapshot.id }) else {
            return "That practice case is no longer open."
        }
        destination.append(Snapshot(item))
        snapshot.apply(to: item)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return "\(name) was not saved: \(error.localizedDescription)"
        }
        return "\(name) restored \(item.title). Press Command-Z to undo and Command-Shift-Z to redo chat edits to a practice note."
    }
}

    private static func upsertCPT(_ stated: StatedCPT, on item: PracticeCase) -> Bool {
        let code = stated.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.range(of: #"^[0-9]{5}(?:-[0-9]{2})?$"#, options: .regularExpression) != nil else {
            return false
        }
        var entries = PracticeCPTStore.load(item.cptDraftData)
        guard !entries.contains(where: { $0.code == code }) else { return false }
        let label = PracticeCPTLibrary.code(code)?.label
            ?? (stated.description.isEmpty ? "Entered in chat" : stated.description)
        entries.append(PracticeCPTEntry(code: code, descriptionText: label))
        item.cptDraftData = PracticeCPTStore.save(entries)
        return true
    }

    private static func currentCase(
        in cases: [PracticeCase],
        conversation: HomeCaseConversation
    ) -> PracticeCase? {
        guard let id = conversation.currentCaseID else { return nil }
        return cases.first { $0.persistentModelID == id }
    }

    private static func references(
        for terms: [String],
        lookup: HomeICDLookup,
        exactCode: Bool
    ) async throws -> ICDReferenceLookup {
        var matches: [ICDReferenceMatch] = []
        var notes: [String] = []
        let uniqueTerms = Array(terms.prefix(exactCode ? 1 : 3))
        guard !uniqueTerms.isEmpty else {
            return ICDReferenceLookup(
                matches: [],
                note: "No history or concern was specific enough to search ICD-10-CM."
            )
        }
        for term in uniqueTerms {
            if matches.count == 3 { break }
            let found = try await lookup.referenceMatches(for: term, limit: exactCode ? 4 : 6)
            if let note = found.note, !note.isEmpty { notes.append(note) }
            for match in found.matches where !matches.contains(where: { $0.code == match.code }) {
                matches.append(match)
                if exactCode || matches.count == 3 { break }
            }
        }
        return ICDReferenceLookup(matches: matches, note: notes.isEmpty ? nil : notes.joined(separator: "\n"))
    }

    private static func formatted(_ attachment: ICDReferenceLookup, term: String) -> String {
        if attachment.matches.isEmpty {
            return attachment.note ?? "No billable local ICD-10-CM match for “\(term)”."
        }
        let rows = attachment.matches.map { "• \($0.code) — \($0.descriptionText)" }.joined(separator: "\n")
        return """
        Local ICD-10-CM references for “\(term)”:
        \(rows)
        \(attachment.note ?? "These are not a final code assignment.")
        """
    }

    private static func sectionName(_ section: PracticeNoteSection) -> String {
        section == .ros ? "ROS" : "physical exam"
    }
}
