import SwiftUI
import SwiftData

@main
struct MADeskAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .modelContainer(for: [PracticeCase.self, PracticeCodeReference.self])
    }
}
