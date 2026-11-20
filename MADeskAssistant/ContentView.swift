import SwiftUI
import Foundation
import Observation
import SwiftData

enum CharacterState: String {
    case idle
    case listening
    case thinking
    case speaking
    case happy
    case alert
    case quiet
    case sleeping
    case error
}

struct DeskTask: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var isComplete: Bool

    init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }
}

struct DeskProfile: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String

    static let all: [DeskProfile] = [
        DeskProfile(id: "sebastian", displayName: "Sebastian"),
        DeskProfile(id: "medical-assistant", displayName: "Medical Assistant"),
        DeskProfile(id: "front-desk", displayName: "Front Desk"),
        DeskProfile(id: "clinician", displayName: "Clinician"),
        DeskProfile(id: "guest", displayName: "Guest")
    ]
}

@Observable
final class AssistantViewModel {
    private let tasksStorageKeyPrefix = "maDeskAssistant.tasks."
    private let selectedUserStorageKey = "maDeskAssistant.selectedUser"
    private let quietModeStorageKey = "maDeskAssistant.quietMode"
    private let sleepingStorageKey = "maDeskAssistant.sleeping"

    var selectedUser = "Sebastian" {
        willSet {
            guard newValue != selectedUser else { return }
            saveTasks(forProfileName: selectedUser)
        }

        didSet {
            guard oldValue != selectedUser else { return }
            saveSettings()
            loadTasksForSelectedProfile()
        }
    }

    var activeProfileID: String {
        profileID(for: selectedUser)
    }

    var characterState: CharacterState = .idle
    var commandText = ""
    var responseText = "Ready when you are. Type “help” to see all commands."
    var isQuietMode = false
    var isSleeping = false
    var tasks: [DeskTask] = []
    var timerRemaining = 0
    var isTimerRunning = false

    private var timer: Timer?

    init() {
        loadSavedData()
    }

    deinit {
        timer?.invalidate()
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good morning, \(selectedUser)."
        } else if hour < 17 {
            return "Good afternoon, \(selectedUser)."
        } else {
            return "Good evening, \(selectedUser)."
        }
    }

    var statusTitle: String {
        if isSleeping { return "Sleeping" }
        if isQuietMode { return "Quiet" }
        return "Active"
    }

    var statusColor: Color {
        if isSleeping { return .indigo }
        if isQuietMode { return .purple }
        return .green
    }

    func submitCommand(cases: [PracticeCase] = [], onUnrecognized: (() -> Void)? = nil) {
        let command = commandText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !command.isEmpty else {
            responseText = "Type a command first, or type “help”."
            characterState = .alert
            return
        }

        if isSleeping &&
            !command.contains("wake up") &&
            !command.contains("wake") {
            responseText = "I am in sleep mode. Type “wake up” to continue."
            characterState = .sleeping
            return
        }

        characterState = .thinking
        responseText = "Thinking..."

        commandText = ""
        handleCommand(command, cases: cases, onUnrecognized: onUnrecognized)
    }

    private func handleCommand(_ command: String, cases: [PracticeCase] = [], onUnrecognized: (() -> Void)? = nil) {
        if command == "help" || command == "commands" || command == "what can you do" || command.contains("help") {
            showHelp()

        } else if command.contains("what time") || command == "time" || command.contains("tell time") {
            tellTime()

        } else if command.contains("diagnosis") || command.contains("assessment") {
            recallAssessment(from: cases)

        } else if command.contains("plan") || command.contains("treatment") {
            recallPlan(from: cases)

        } else if command.contains("summarize") || command.contains("summary") {
            summarizeLatestCase(from: cases)

        } else if command.contains("my cases") || command.contains("list cases") {
            listCases(from: cases)

        } else if command.contains("quiet mode") || command.contains("be quiet") || command.contains("mute") {
            enableQuietMode()

        } else if command.contains("wake up") || command.contains("wake") || command.contains("turn on sound") || command.contains("unmute") {
            wakeUp()

        } else if command.contains("sleep mode") || command.contains("go to sleep") || command.contains("go sleep") {
            enableSleepMode()

        } else if command.contains("tell me a joke") || command.contains("joke") {
            tellJoke()

        } else if command.contains("show tasks") || command.contains("my tasks") || command.contains("show task list") {
            showTasks()

        } else if isAddTaskCommand(command) {
            addTask(from: command)

        } else if command.contains("complete task") || command.contains("finish task") {
            completeTask(from: command)

        } else if command.contains("cancel timer") || command.contains("stop timer") {
            cancelTimer()

        } else if command.contains("timer") {
            let minutes = extractMinutes(from: command) ?? 5
            startTimer(minutes: minutes)

        } else if command.contains("water") && (command.contains("plant") || command.contains("pothos") || command.contains("snake plant")) {
            plantResponse()

        } else if command.contains("medicine") || command.contains("medication") || command.contains("dosage") || command.contains("dose") || command.contains("prescription") {
            medicalSafetyResponse()

        } else if command.contains("calendar") {
            responseText = "Calendar integration is planned for the next version. This prototype currently runs local features only."
            characterState = .idle

        } else if command.contains("news") {
            responseText = "News lookup will be added when we connect the app to a web-search service."
            characterState = .idle

        } else if let onUnrecognized {
            onUnrecognized()
        } else {
            responseText = """
            I don’t recognize that command.
            Type “help” to view all available commands.
            """
            characterState = .idle
        }
    }

    private func showHelp() {
        responseText = """
        Available Commands:

        📝 Practice Notes:
        • “Start a note. Patient is a 60 year old with h/o hypertension and c/o cough, and wants a work note.”
        • “Remove night sweats from ROS”
        • “Add sore throat to ROS”
        • “Remove wheeze from PE”
        • “What diagnosis did I document?”
        • “What is the plan?”
        • “Summarize my last case”
        • “List my cases”

        🔎 Codes for review, not a final assignment:
        • “What is the code for diabetes?”
        • “Find codes for hypertension”
        • “ICD-10 asthma”
        • “Add ICD cough” / “Remove ICD R05.9”
        • “Add CPT 99213 established office visit” / “Remove CPT 99213”
        • “What is a CPT code?”

        📋 Tasks:
        • “Add task [title]” (e.g. “Add task call pharmacy”)
        • “Show tasks”
        • “Complete task”

        ⏱️ Timers & Utilities:
        • “Set a [X] minute timer” (e.g. “Set a 15 minute timer”)
        • “Cancel timer”
        • “What time is it?”

        🤖 Assistant Controls:
        • “Quiet mode” / “Wake up”
        • “Sleep mode”
        • “Tell me a joke”
        • “Water plant”
        """
        characterState = .happy
    }

    private func recallAssessment(from cases: [PracticeCase]) {
        guard let latest = cases.first else {
            responseText = "No saved fictional cases found for \(selectedUser)."
            characterState = .idle
            return
        }

        let assessmentText = latest.assessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if assessmentText.isEmpty {
            responseText = "Case “\(latest.title)” has no assessment entered yet."
        } else {
            responseText = "Documented assessment for “\(latest.title)”:\n\(assessmentText)\n\n(Source: Saved fictional note. Not a live clinical diagnosis.)"
        }
        characterState = .happy
    }

    private func recallPlan(from cases: [PracticeCase]) {
        guard let latest = cases.first else {
            responseText = "No saved fictional cases found for \(selectedUser)."
            characterState = .idle
            return
        }

        let planText = latest.plan.trimmingCharacters(in: .whitespacesAndNewlines)
        if planText.isEmpty {
            responseText = "Case “\(latest.title)” has no plan entered yet."
        } else {
            responseText = "Documented plan for “\(latest.title)”:\n\(planText)\n\n(Source: Saved fictional note.)"
        }
        characterState = .happy
    }

    private func summarizeLatestCase(from cases: [PracticeCase]) {
        guard let latest = cases.first else {
            responseText = "No saved fictional cases found for \(selectedUser)."
            characterState = .idle
            return
        }

        let r = latest.reasonForVisit.isEmpty ? "Not entered" : latest.reasonForVisit
        let h = latest.hpi.isEmpty ? "Not entered" : latest.hpi
        let a = latest.assessment.isEmpty ? "Not entered" : latest.assessment
        let p = latest.plan.isEmpty ? "Not entered" : latest.plan

        responseText = "Summary of “\(latest.title)”:\n• Reason: \(r)\n• HPI: \(h)\n• Assessment: \(a)\n• Plan: \(p)"
        characterState = .happy
    }

    private func listCases(from cases: [PracticeCase]) {
        if cases.isEmpty {
            responseText = "\(selectedUser) has no saved fictional cases."
        } else {
            let titles = cases.prefix(3).map(\.title).joined(separator: ", ")
            responseText = "\(selectedUser) has \(cases.count) saved case\(cases.count == 1 ? "" : "s"): \(titles)."
        }
        characterState = .happy
    }

    private func isAddTaskCommand(_ command: String) -> Bool {
        let normalized = command
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let taskPrefixes = [
            "add task", "add a task", "new task", "create task",
            "create a task", "make task", "make a task", "remember to",
            "remind me to", "please add task", "please add a task"
        ]

        return taskPrefixes.contains { normalized.hasPrefix($0) }
    }

    private func profileID(for profileName: String) -> String {
        DeskProfile.all.first(where: {
            $0.displayName == profileName
        })?.id ?? "guest"
    }

    private func tasksStorageKey(for profileName: String) -> String {
        "\(tasksStorageKeyPrefix)\(profileID(for: profileName))"
    }

    private var tasksStorageKey: String {
        tasksStorageKey(for: selectedUser)
    }

    private func loadSavedData() {
        let defaults = UserDefaults.standard
        selectedUser = defaults.string(forKey: selectedUserStorageKey) ?? "Sebastian"
        isQuietMode = defaults.bool(forKey: quietModeStorageKey)
        isSleeping = defaults.bool(forKey: sleepingStorageKey)
        loadTasksForSelectedProfile()
    }

    private func loadTasksForSelectedProfile() {
        let defaults = UserDefaults.standard
        guard let savedTasksData = defaults.data(forKey: tasksStorageKey),
              let decodedTasks = try? JSONDecoder().decode([DeskTask].self, from: savedTasksData) else {
            tasks = []
            return
        }
        tasks = decodedTasks
    }

    func saveTasks() {
        saveTasks(forProfileName: selectedUser)
    }

    private func saveTasks(forProfileName profileName: String) {
        guard let encodedTasks = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(encodedTasks, forKey: tasksStorageKey(for: profileName))
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedUser, forKey: selectedUserStorageKey)
        defaults.set(isQuietMode, forKey: quietModeStorageKey)
        defaults.set(isSleeping, forKey: sleepingStorageKey)
    }

    func tellTime() {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        responseText = "It is \(formatter.string(from: Date()))."
        characterState = .happy
    }

    func enableQuietMode() {
        isQuietMode = true
        isSleeping = false
        saveSettings()
        responseText = "Quiet mode is on. I will keep notifications silent."
        characterState = .quiet
    }

    func disableQuietMode() {
        isQuietMode = false
        isSleeping = false
        saveSettings()
        responseText = "Quiet mode is off. Sound is enabled."
        characterState = .happy
    }

    func enableSleepMode() {
        isSleeping = true
        isQuietMode = true
        saveSettings()
        responseText = "Sleep mode enabled. Type “wake up” when you need me."
        characterState = .sleeping
    }

    func wakeUp() {
        isSleeping = false
        isQuietMode = false
        saveSettings()
        responseText = "I am awake and ready."
        characterState = .happy
    }

    func tellJoke() {
        let jokes = [
            "Why did the cell go to therapy? It had too many issues with its membrane.",
            "Why do biologists look forward to casual Fridays? They are allowed to wear genes.",
            "What did one neuron say to another neuron? I think I am losing my mind.",
            "Why did the medical student bring a ladder? To reach the next level of training."
        ]
        responseText = jokes.randomElement() ?? "I had a joke, but it divided by zero."
        characterState = .happy
    }

    func showTasks() {
        let incompleteTasks = tasks.filter { !$0.isComplete }
        if incompleteTasks.isEmpty {
            responseText = "You have no unfinished tasks."
        } else {
            let taskNames = incompleteTasks.prefix(3).map(\.title).joined(separator: ", ")
            responseText = "You have \(incompleteTasks.count) unfinished task\(incompleteTasks.count == 1 ? "" : "s"): \(taskNames)."
        }
        characterState = .happy
    }

    func addTask(from command: String) {
        let prefixes = [
            "add task", "add a task", "new task", "create task",
            "create a task", "make task", "make a task", "remember to",
            "remind me to", "please add task", "please add a task"
        ]

        var taskTitle = command
        for prefix in prefixes {
            if command.hasPrefix(prefix) {
                taskTitle = command
                    .replacingOccurrences(of: prefix, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        guard !taskTitle.isEmpty else {
            responseText = "Tell me what task you want to add. Example: “Add task call pharmacy.”"
            characterState = .alert
            return
        }

        let formattedTitle = taskTitle.capitalized
        tasks.append(DeskTask(title: formattedTitle))
        saveTasks()
        responseText = "Added task: \(formattedTitle)."
        characterState = .happy
    }

    func completeTask(from command: String) {
        let incompleteTasks = tasks.filter { !$0.isComplete }
        guard let firstTask = incompleteTasks.first else {
            responseText = "You do not have any unfinished tasks to complete."
            characterState = .idle
            return
        }

        toggleTask(firstTask)
        responseText = "Marked “\(firstTask.title)” as complete."
        characterState = .happy
    }

    func plantResponse() {
        responseText = "Plant reminder noted. Check the soil first: water when the top 1–2 inches are dry for most houseplants."
        characterState = .happy
    }

    func medicalSafetyResponse() {
        responseText = "Medical-reference mode is not active yet. This assistant may later provide general educational information and transparent calculators, but it must not diagnose, prescribe, or give patient-specific dosing advice."
        characterState = .alert
    }

    func extractMinutes(from command: String) -> Int? {
        let words = command.split(separator: " ")
        for word in words {
            let cleanedWord = word
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
            if let value = Int(cleanedWord), value > 0, value <= 240 {
                return value
            }
        }
        return nil
    }

    func startTimer(minutes: Int) {
        timer?.invalidate()
        timerRemaining = minutes * 60
        isTimerRunning = true
        responseText = "Timer started for \(minutes) minute\(minutes == 1 ? "" : "s")."
        characterState = .happy

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] activeTimer in
            guard let self else {
                activeTimer.invalidate()
                return
            }
            if self.timerRemaining > 0 {
                self.timerRemaining -= 1
            } else {
                activeTimer.invalidate()
                self.isTimerRunning = false
                self.responseText = "Your timer is complete."
                self.characterState = .alert
            }
        }
    }

    func cancelTimer() {
        timer?.invalidate()
        timer = nil
        timerRemaining = 0
        isTimerRunning = false
        responseText = "Timer cancelled."
        characterState = .idle
    }

    func formattedTimer() -> String {
        let minutes = timerRemaining / 60
        let seconds = timerRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func toggleTask(_ task: DeskTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        if tasks[index].isComplete {
            responseText = "Completed task: \(tasks[index].title)."
            characterState = .happy
        } else {
            responseText = "Reopened task: \(tasks[index].title)."
            characterState = .idle
        }
        saveTasks()
    }
}

struct CharacterView: View {
    let state: CharacterState

    @State private var blink = false
    @State private var pulse = false
    @State private var lookOffset: CGFloat = 0
    @State private var eyeScale: CGFloat = 1.0

    private var eyeColor: Color {
        switch state {
        case .idle: return .cyan
        case .listening: return .green
        case .thinking: return .orange
        case .speaking: return .blue
        case .happy: return .mint
        case .alert: return .yellow
        case .quiet: return .purple
        case .sleeping: return .indigo
        case .error: return .red
        }
    }

    private var eyeHeight: CGFloat {
        state == .sleeping ? 10 : (blink ? 8 : 84)
    }

    var body: some View {
        HStack(spacing: 74) {
            eye
            eye
        }
        .offset(x: lookOffset)
        .scaleEffect(eyeScale)
        .onAppear {
            configureAnimations()
        }
        .onChange(of: state) { _, _ in
            configureAnimations()
        }
    }


    private var eye: some View {
        Capsule()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.98), eyeColor, eyeColor.opacity(0.30)],
                    center: .center,
                    startRadius: 2,
                    endRadius: 70
                )
            )
            .frame(width: 82, height: eyeHeight)
            .shadow(color: eyeColor.opacity(pulse ? 0.95 : 0.45), radius: pulse ? 36 : 18)
            .animation(.easeInOut(duration: 0.12), value: blink)
            .animation(.easeInOut(duration: 0.45), value: eyeHeight)
    }

    private func configureAnimations() {
        blink = false
        lookOffset = 0
        eyeScale = 1.0
        pulse = false

        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
            pulse = true
        }

        if state == .sleeping {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                eyeScale = 0.94
            }
            return
        }

        if state == .thinking {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                lookOffset = 14
            }
        }

        if state == .happy {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).repeatForever(autoreverses: true)) {
                eyeScale = 1.06
            }
        }

        scheduleBlink()
    }

    private var pulseDuration: Double {
        switch state {
        case .thinking: return 0.55
        case .listening: return 0.75
        case .alert: return 0.45
        case .sleeping: return 2.0
        default: return 1.5
        }
    }

    private func scheduleBlink() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            guard state != .sleeping else { return }
            blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                blink = false
                scheduleBlink()
            }
        }
    }
}

@MainActor
struct ContentView: View {
    @Bindable var assistant: AssistantViewModel
    let ai: LocalAIService
    @Environment(\.modelContext) private var modelContext
    @State private var homeICDLookup = HomeICDLookup()
    @State private var generationTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var isGenerating = false
    @State private var practiceNoteTask = false
    @State private var caseConversation = HomeCaseConversation()
    @State private var showCaseBrowser = false
    @Query(sort: \PracticeCase.updatedAt, order: .reverse) private var allCases: [PracticeCase]
    

    private var profileCases: [PracticeCase] {
        let owner = assistant.activeProfileID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !owner.isEmpty else { return [] }
        return allCases.filter {
            guard let id = $0.ownerProfileID else { return false }
            return id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == owner
        }
    }

    var body: some View {
        ZStack {
            background
            ScrollView(.vertical) {
                VStack(spacing: 22) {
                    header
                    CharacterView(state: assistant.characterState)
                        .frame(height: 150)
                        .padding(.top, 16)
                    Text(assistant.greeting)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Assistant response", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))
                        Text(assistant.responseText)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: 790, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    if let title = caseConversation.currentTitle {
                        HStack {
                            Label("Current chat case: \(title)", systemImage: "doc.text")
                                .font(.caption)
                            Spacer()
                            Button("Clear") {
                                caseConversation.reset()
                                assistant.responseText = "Current chat case cleared."
                            }
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: 790)
                        .disabled(isGenerating)
                    }

                    if assistant.isTimerRunning { timerPanel }
                    commandPanel

                    DisclosureGroup("Browse cases — optional exact-text controls", isExpanded: $showCaseBrowser) {
                        HomeCaseRecallView(activeProfileID: assistant.activeProfileID) { answer in
                            cancelGeneration()
                            // The optional browser has its own picker; do not imply it sets chat context.
                            caseConversation.reset()
                            assistant.responseText = answer
                            assistant.characterState = .idle
                        }
                        .padding(.top, 8)
                        .disabled(isGenerating)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: 790)

                    taskPanel
                }
                .padding(28)
                .frame(maxWidth: 1_100)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 740)
        .onChange(of: assistant.activeProfileID) { _, _ in
            cancelGeneration()
            caseConversation.reset()
            showCaseBrowser = false
            assistant.commandText = ""
            assistant.responseText = "Profile changed. Ready for a new request."
            assistant.characterState = assistant.isSleeping ? .sleeping : .idle
        }
        .onChange(of: profileCases.map(\.persistentModelID)) { _, _ in
            guard caseConversation.currentCaseWasRemoved(from: profileCases) else { return }
            caseConversation.reset()
            assistant.responseText = "The selected chat case is no longer in this profile. Select it again by title or identifier."
            assistant.characterState = .alert
        }
        .onDisappear {
            cancelGeneration()
            caseConversation.reset()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [.black, Color(red: 0.015, green: 0.035, blue: 0.09), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MA Desk Assistant")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(
                    Date.now,
                    format: .dateTime.weekday(.wide).month().day().year().hour().minute()
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Picker("Profile", selection: $assistant.selectedUser) {
                ForEach(DeskProfile.all) { profile in
                    Text(profile.displayName)
                        .tag(profile.displayName)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 175)

            statusPill(
                title: assistant.statusTitle,
                color: assistant.statusColor
            )
        }
    }

    private var timerPanel: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text(assistant.formattedTimer())
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Button("Cancel Timer") {
                assistant.cancelTimer()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var commandPanel: some View {
        HStack(spacing: 12) {
            TextField(
                "Start a note, ask a question, or type help",
                text: $assistant.commandText
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 16))
            .onSubmit {
                submitHomeInput()
            }

            Button {
                submitHomeInput()
            } label: {
                Label("Ask", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(isGenerating)

            if isGenerating {
                ProgressView().controlSize(.small)
                Button("Stop") { cancelGeneration() }
            }

            Button {
                if assistant.isQuietMode {
                    assistant.disableQuietMode()
                } else {
                    assistant.enableQuietMode()
                }
            } label: {
                Image(systemName: assistant.isQuietMode ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .help("Toggle quiet mode")

            Button {
                if assistant.isSleeping {
                    assistant.wakeUp()
                } else {
                    assistant.enableSleepMode()
                }
            } label: {
                Image(systemName: assistant.isSleeping ? "sun.max.fill" : "moon.fill")
            }
            .buttonStyle(.bordered)
            .help("Toggle sleep mode")
        }
        .frame(maxWidth: 790)
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(assistant.tasks.filter { !$0.isComplete }.count) remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Divider()
                .overlay(.white.opacity(0.15))

            if assistant.tasks.allSatisfy({ $0.isComplete }) {
                Text("No tasks yet.")
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(assistant.tasks.filter { !$0.isComplete }) { task in
                    Button {
                        assistant.toggleTask(task)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isComplete ? .green : .white.opacity(0.65))

                            Text(task.title)
                                .strikethrough(task.isComplete)
                                .foregroundStyle(task.isComplete ? .white.opacity(0.40) : .white)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 790, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }

    private func submitHomeInput() {
        guard !isGenerating else { return }

        let input = assistant.commandText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !input.isEmpty else {
            assistant.responseText = "Enter a question or command first."
            assistant.characterState = .alert
            return
        }

        if assistant.isSleeping {
            assistant.submitCommand(cases: profileCases)
            return
        }

        if let action = PracticeNoteChatRouter.action(for: input) {
            assistant.commandText = ""
            beginPracticeNote(action)
            return
        }

        // Search the package before case routing or AI generation.
        if let term = HomeICDLookup.searchTerm(from: input) {
            assistant.commandText = ""
            searchHomeICD(term)
            return
        }

        if input.lowercased().hasPrefix("ai ") {
            assistant.commandText = ""
            generateReply(String(input.dropFirst(3)))
            return
        }

        if let answer = caseConversation.handle(
            input,
            cases: profileCases,
            profileID: assistant.activeProfileID
        ) {
            assistant.commandText = ""
            assistant.responseText = answer
            assistant.characterState = .idle
            return
        }

        assistant.submitCommand(cases: profileCases) {
            generateReply(input)
        }
    }


    private func generateReply(_ input: String) {
        guard !input.isEmpty else { return }
        assistant.responseText = """
        \(ai.unavailableMessage)

        Practice notes, ICD-10 lookup, tasks, and dictation still work.
        Example: “Start a note. Patient is a 60 year old with h/o hypertension and c/o cough.”
        Or: “What is the code for cough?”

        Your message was: \(input)
        """
        assistant.characterState = .idle
    }

    private func searchHomeICD(_ term: String) {
        let id = UUID()
        let profile = assistant.activeProfileID

        requestID = id
        isGenerating = true
        assistant.characterState = .thinking
        assistant.responseText = "Searching the local ICD-10-CM database…"

        generationTask = Task { @MainActor in
            defer {
                if requestID == id {
                    requestID = nil
                    isGenerating = false
                    generationTask = nil
                }
            }

            do {
                let answer = try await homeICDLookup.search(term)

                try Task.checkCancellation()

                guard requestID == id,
                      assistant.activeProfileID == profile else {
                    return
                }

                assistant.responseText = answer
                assistant.characterState = .idle
            } catch is CancellationError {
                if requestID == id, assistant.activeProfileID == profile {
                    assistant.responseText = "ICD-10-CM search canceled."
                    assistant.characterState = .idle
                }
            } catch {
                guard requestID == id,
                      assistant.activeProfileID == profile else {
                    return
                }

                assistant.responseText = """
                Local ICD-10-CM lookup failed:
                \(error)

                No AI-generated code was substituted.
                """
                assistant.characterState = .error
            }
        }
    }

    private func beginPracticeNote(_ action: PracticeNoteChatAction) {
        switch action {
        case .explainCPT:
            assistant.responseText = PracticeNoteChatRouter.cptHelp
            assistant.characterState = .idle
            return
        case .explainICD:
            assistant.responseText = PracticeNoteChatRouter.icdHelp
            assistant.characterState = .idle
            return
        default:
            break
        }

        let id = UUID()
        let profile = assistant.activeProfileID
        let profileName = assistant.selectedUser
        requestID = id
        isGenerating = true
        practiceNoteTask = true
        assistant.characterState = .thinking
        assistant.responseText = "Preparing the fictional practice note…"
        generationTask = Task { @MainActor in
            defer {
                if requestID == id {
                    requestID = nil
                    isGenerating = false
                    practiceNoteTask = false
                    generationTask = nil
                }
            }
            do {
                let message = try await HomePracticeNoteController.perform(
                    action,
                    profileID: profile,
                    profileName: profileName,
                    cases: profileCases,
                    conversation: caseConversation,
                    modelContext: modelContext,
                    lookup: homeICDLookup
                )
                try Task.checkCancellation()
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = message
                assistant.characterState = .happy
            } catch is CancellationError {
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = "Stopped. Check Practice Cases before starting another draft. A note is saved only if it is listed there."
                assistant.characterState = .idle
            } catch {
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = """
                The practice note could not be finished:
                \(error)

                No AI-generated code was substituted.
                """
                assistant.characterState = .error
            }
        }
    }

    private func cancelGeneration() {
        let active = isGenerating
        let noteTask = practiceNoteTask
        requestID = nil
        practiceNoteTask = false
        homeICDLookup.cancel()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        if active {
            assistant.responseText = noteTask
                ? "Stopped. Check Practice Cases before starting another draft. A note is saved only if it is listed there."
                : "Generation stopped. Partial draft discarded."
            assistant.characterState = .idle
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: Capsule())
    }
}

#Preview {
    ContentView(assistant: AssistantViewModel(), ai: LocalAIService())
}
