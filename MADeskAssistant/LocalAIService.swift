//
//  LocalAIService.swift
//  MADeskAssistant
//
//  Uses the on-device Apple language model. Questions stay on this Mac.
//

import Foundation
import FoundationModels
import Observation

@MainActor
@Observable
final class LocalAIService {
    var isLoading = false
    private(set) var statusMessage = "Checking the on-device model."
    private var session: LanguageModelSession?
    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    func prepareIfNeeded() async {
        guard session == nil else { return }
        isLoading = true
        defer { isLoading = false }
        switch model.availability {
        case .available:
            session = LanguageModelSession(model: model, instructions: Self.instructions)
            session?.prewarm()
            statusMessage = "On-device Apple model is ready. It answers questions that are not desk commands. Text stays on this Mac."
        case .unavailable(let reason):
            session = nil
            statusMessage = Self.message(for: reason)
        }
    }

    func reply(
        to input: String,
        caseContext: String,
        earlierUser: String = "",
        earlierReply: String = "",
        style: HomeReplyStyle = .usual,
        taskContext: String = "Not requested.",
        revising: Bool = false
    ) async throws -> String {
        await prepareIfNeeded()
        guard let session else {
            return """
            \(statusMessage)

            Note, ICD-10, and CPT commands still work. Nothing was saved to a practice case.
            """
        }
        let length: String
        switch style {
        case .brief:
            length = "Use one or two short sentences."
        case .detailed:
            length = "You may use a short paragraph. Stay on the question."
        case .usual:
            length = "Use a few short sentences."
        }
        let focus = revising
            ? "They want the previous reply rewritten. Do that. Do not switch to the practice case."
            : "Use the previous reply only when their new message refers to it, such as “that”, “the second one”, or “shorter”."
        let prompt = """
        \(length)
        \(focus)
        Sound like a person helping at the desk. Do not list commands unless they asked what you can do.

        Previous message:
        \(Self.promptText(earlierUser, limit: 500))

        Your previous reply:
        \(Self.promptText(earlierReply, limit: 1_200))

        Open fictional practice case, retrieved by the app:
        \(caseContext)

        Desk tasks, retrieved by the app. Suggest an order only if they asked about tasks. Do not say a task was completed.
        \(taskContext)

        New message:
        \(input)
        """
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "The on-device model returned an empty reply. Nothing was saved to a practice case."
        }
        return """
        \(text)

        Practice draft from the on-device model. Not a diagnosis or a billing decision. Nothing was saved to a practice case.
        """
    }

    private static func promptText(_ text: String, limit: Int) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let footer = "Practice draft from the on-device model. Not a diagnosis or a billing decision. Nothing was saved to a practice case."
        if let range = value.range(of: footer) {
            value.removeSubrange(range)
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "None." }
        if value.count > limit {
            return String(value.prefix(limit)) + "…"
        }
        return value
    }

    private static let instructions = """
    You are MA Desk, talking with the person at the desk about fictional practice work.
    The app already decided which case and which tasks you can see. Use only that text.
    If no case is open, say so and do not invent a note.
    You cannot change a note, choose a diagnosis, choose a billing code, or mark a task complete.
    If they ask you to save or add something, say what they can type, such as “Start a note” or “Add CPT 99213”, and do not claim it was saved.
    If something is missing from the open note, name the missing part.
    If there is no previous reply and they refer to one, say you do not have one yet.
    Treat every clinical detail as fictional practice material, not validated medical guidance.
    """

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off, so the on-device model cannot answer yet. Turn it on in System Settings, then reopen Local AI."
        case .deviceNotEligible:
            return "This Mac cannot run the on-device Apple model. Note, ICD-10, and CPT commands still work."
        case .modelNotReady:
            return "The on-device model is not ready yet. Wait for Apple Intelligence to finish downloading, then reopen Local AI."
        @unknown default:
            return "The on-device model is unavailable. Note, ICD-10, and CPT commands still work."
        }
    }
}
