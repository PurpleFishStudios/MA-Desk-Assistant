import SwiftUI

struct AppShellView: View {
    @State private var dictation = DeskDictationModule()
    @State private var selectedSection: AppSection? = .home
    @State private var assistant = AssistantViewModel()
    @State private var localAI = LocalAIService()



    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("MA Desk Assistant")
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .frame(minWidth: 1_000, minHeight: 740)
        .environment(dictation)
        .task {
            await localAI.prepareIfNeeded()
        }
        .onChange(of: assistant.activeProfileID) { _, _ in
            dictation.discard()
        }

    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .home {
        case .home:
            ContentView(assistant: assistant, ai: localAI)

        case .tasks:
            TasksView(assistant: assistant)

        case .practiceCases:
            PracticeCasesView(
                activeProfileID: assistant.activeProfileID,
                activeProfileName: assistant.selectedUser
            )

        case .timers:
            PlaceholderScreen(
                title: "Timers",
                systemImage: "timer",
                message: "Your timer history and controls will go here next."
            )

        case .plants:
            PlaceholderScreen(
                title: "Plants",
                systemImage: "leaf.fill",
                message: "Plant profiles and watering schedules will go here next."
            )

        case .icd10:
            ICD10ReferenceView()

        case .dictation:
            DictationTestView(profileName: assistant.selectedUser)

        case .localAI:
            LocalAITestView(ai: localAI)


        case .settings:
            PlaceholderScreen(
                title: "Settings",
                systemImage: "gearshape.fill",
                message: "Profile, notification, personality, and privacy settings will go here."
            )
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(.cyan)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    AppShellView()
}

