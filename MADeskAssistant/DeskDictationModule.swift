import Foundation
import Observation
import WhisperKit

@MainActor
@Observable
final class DeskDictationModule {
    private(set) var isBusy = false
    private(set) var isReady = false
    private(set) var status = "Model not loaded. Prepare it when you are ready."
    var transcript = ""

    @ObservationIgnored private var engine: WhisperKit?
    @ObservationIgnored private var requestID: UUID?

    init() {}

    func prepare() async {
        guard !isBusy, engine == nil else { return }
        isBusy = true
        status = "Preparing tiny.en model. The first run may download model files…"
        defer { isBusy = false }
        do {
            engine = try await WhisperKit(WhisperKitConfig(model: "tiny.en"))
            isReady = true
            status = "Model ready. Choose a short fictional English recording."
        } catch {
            engine = nil
            isReady = false
            status = "Model preparation failed: \(error.localizedDescription)"
        }
    }

    func transcribe(_ url: URL) async {
        guard !isBusy, let engine else { return }
        let id = UUID()
        requestID = id
        isBusy = true
        transcript = ""
        status = "Transcribing locally…"
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            isBusy = false
            if requestID == id {
                requestID = nil
            } else {
                status = "Previous result discarded. Ready for another recording."
            }
        }
        do {
            let results = try await engine.transcribe(audioPath: url.path)
            guard requestID == id else { return }
            transcript = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            status = transcript.isEmpty
                ? "No transcript returned. Try a clearer recording."
                : "Draft ready. Review every word before using it."
        } catch {
            guard requestID == id else { return }
            status = "Transcription failed: \(error.localizedDescription)"
        }
    }

    func discard() {
        requestID = nil
        transcript = ""
        if isBusy {
            status = "Discarding pending result. Processing may continue until completion."
        } else {
            status = isReady ? "Transcript cleared. Model ready." : "Model not loaded."
        }
    }
}
