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

    func reply(to input: String, caseContext: String) async throws -> String {
        await prepareIfNeeded()
        guard let session else {
            return """
            \(statusMessage)

            Note, ICD-10, and CPT commands still work. Nothing was saved to a practice case.
            """
        }
        let prompt = """
        Open fictional practice case:
        \(caseContext)

        Question:
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

    private static let instructions = """
    You are MA Desk, a desk assistant for fictional practice cases.
    Answer in a few short sentences.
    The question includes the open practice case when one is open. Use only that text.
    If no case is open, say so and do not invent a note.
    You cannot change a note, choose a diagnosis, or choose a billing code.
    If something is missing from the note, name the missing part.
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
