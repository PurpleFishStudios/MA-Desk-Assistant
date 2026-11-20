import SwiftUI
import UniformTypeIdentifiers

struct DictationTestView: View {
    @Environment(DeskDictationModule.self) private var dictation
    @State private var showImporter = false
    @State private var importError: String?
    let profileName: String

    var body: some View {
        @Bindable var dictation = dictation
        VStack(alignment: .leading, spacing: 18) {
            Label("Dictation Test", systemImage: "waveform")
                .font(.largeTitle.weight(.semibold))
            Text("Profile: \(profileName)")
                .foregroundStyle(.secondary)
            Text("Fictional recordings only. This screen does not record your microphone, save notes, or submit assistant commands.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Prepare English Test Model") {
                    Task { await dictation.prepare() }
                }
                .disabled(dictation.isBusy || dictation.isReady)
                Button("Choose Audio File") { showImporter = true }
                    .disabled(dictation.isBusy || !dictation.isReady)
                Button("Discard Transcript") { dictation.discard() }
                    .disabled(dictation.isBusy || dictation.transcript.isEmpty)
                if dictation.isBusy { ProgressView().controlSize(.small) }
            }
            Text(dictation.status)
                .font(.callout)
                .textSelection(.enabled)
            if let importError {
                Text(importError).foregroundStyle(.red)
            }
            Text("Review and edit the draft below:")
                .font(.headline)
            TextEditor(text: $dictation.transcript)
                .font(.body)
                .frame(minHeight: 250)
                .disabled(dictation.isBusy)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
            Text("Transcripts are temporary and are cleared when leaving this screen or changing profiles. The small English model is for integration testing, not clinical validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                importError = nil
                Task { await dictation.transcribe(url) }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .onDisappear { dictation.discard() }
    }
}
