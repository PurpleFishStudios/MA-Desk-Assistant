//
//  LocalAITestView.swift
//  MADeskAssistant
//

import SwiftUI

struct LocalAITestView: View {
    let ai: LocalAIService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Local AI", systemImage: "brain.head.profile")
                .font(.largeTitle.bold())

            Text(ai.unavailableMessage)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("ICD-10 lookup, practice notes, tasks, and dictation do not use this model.")
                .font(.callout)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Local AI")
    }
}
