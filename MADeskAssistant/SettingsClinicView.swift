//
//  SettingsClinicView.swift
//  MADeskAssistant
//

import SwiftUI

struct DeskEyeColor: Identifiable, Hashable {
    let name: String
    let color: Color
    var id: String { name }

    static let choices: [DeskEyeColor] = [
        DeskEyeColor(name: "Cyan", color: .cyan),
        DeskEyeColor(name: "Blue", color: Color(red: 0.25, green: 0.55, blue: 1)),
        DeskEyeColor(name: "Mint", color: .mint),
        DeskEyeColor(name: "Teal", color: .teal),
        DeskEyeColor(name: "Purple", color: .purple),
        DeskEyeColor(name: "White", color: .white)
    ]

    static func color(named name: String) -> Color {
        choices.first { $0.name == name }?.color ?? .cyan
    }
}

struct SettingsClinicView: View {
    @Bindable var assistant: AssistantViewModel
    @State private var newName = ""
    @State private var rename = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Clinic profiles keep fictional practice notes separate. Eye color is only for the Home assistant.")
                    .foregroundStyle(.secondary)

                GroupBox("Eye color") {
                    Picker("Eye color", selection: $assistant.eyeColorName) {
                        ForEach(DeskEyeColor.choices) { choice in
                            Text(choice.name).tag(choice.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: assistant.eyeColorName) { _, _ in
                        assistant.saveSettings()
                    }
                }

                GroupBox("Clinic profiles") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(assistant.profiles) { profile in
                            HStack {
                                Text(profile.displayName)
                                if profile.displayName == assistant.selectedUser {
                                    Text("Active")
                                        .font(.caption)
                                        .foregroundStyle(.cyan)
                                }
                                Spacer()
                                Button("Use") { assistant.selectedUser = profile.displayName }
                                Button("Remove", role: .destructive) {
                                    assistant.removeProfile(profile)
                                }
                                .disabled(assistant.profiles.count < 2)
                            }
                        }

                        TextField("New profile name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add profile") {
                            assistant.addProfile(named: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        TextField("Rename the active profile", text: $rename)
                            .textFieldStyle(.roundedBorder)
                        Button("Rename active profile") {
                            assistant.renameActiveProfile(to: rename)
                            rename = ""
                        }
                        .disabled(rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Settings")
    }
}
