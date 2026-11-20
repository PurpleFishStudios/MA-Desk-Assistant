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

            Text(ai.statusMessage)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(ai.isAvailable
                 ? "Ask a normal question on Home. Note edits, ICD-10 lookup, and CPT codes still use the desk commands."
                 : "The desk commands do not need this model.")
                .font(.callout)

            if ai.isLoading {
                ProgressView("Checking the on-device model")
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Local AI")
        .task { await ai.prepareIfNeeded() }
    }
}
