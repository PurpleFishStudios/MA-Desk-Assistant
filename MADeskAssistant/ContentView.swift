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
    var id: String
    var displayName: String

    static let storageKey = "maDeskAssistant.profiles"
    static let builtIn: [DeskProfile] = [
        DeskProfile(id: "sebastian", displayName: "Sebastian"),
        DeskProfile(id: "medical-assistant", displayName: "Medical Assistant"),
        DeskProfile(id: "front-desk", displayName: "Front Desk"),
        DeskProfile(id: "clinician", displayName: "Clinician"),
        DeskProfile(id: "guest", displayName: "Guest")
    ]

    static func load() -> [DeskProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([DeskProfile].self, from: data),
              !saved.isEmpty else { return builtIn }
        return saved
    }

    static func save(_ profiles: [DeskProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
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
    var eyeColorName = "Cyan"
    var profiles: [DeskProfile] = DeskProfile.load()

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
        profiles.first(where: {
            $0.displayName == profileName
        })?.id ?? profiles.first?.id ?? "guest"
    }

    func addProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
        guard !profiles.contains(where: { $0.id == id || $0.displayName.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else {
            responseText = "A profile named \(trimmed) already exists."
            return
        }
        profiles.append(DeskProfile(id: id, displayName: trimmed))
        DeskProfile.save(profiles)
        selectedUser = trimmed
        responseText = "Added clinic profile \(trimmed). New fictional notes stay on this profile."
        characterState = .happy
    }

    func removeProfile(_ profile: DeskProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        DeskProfile.save(profiles)
        if selectedUser == profile.displayName {
            selectedUser = profiles[0].displayName
        }
        responseText = "Removed profile \(profile.displayName). Its saved notes stay in the data store and are not deleted."
        characterState = .idle
    }

    func renameActiveProfile(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.displayName == selectedUser }) else { return }
        profiles[index].displayName = trimmed
        DeskProfile.save(profiles)
        selectedUser = trimmed
        responseText = "Renamed the active profile to \(trimmed)."
        characterState = .happy
    }

    private func tasksStorageKey(for profileName: String) -> String {
        "\(tasksStorageKeyPrefix)\(profileID(for: profileName))"
    }

    private var tasksStorageKey: String {
        tasksStorageKey(for: selectedUser)
    }

    private func loadSavedData() {
        let defaults = UserDefaults.standard
        profiles = DeskProfile.load()
        selectedUser = defaults.string(forKey: selectedUserStorageKey) ?? profiles.first?.displayName ?? "Sebastian"
        eyeColorName = defaults.string(forKey: "maDeskAssistant.eyeColor") ?? "Cyan"
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
        defaults.set(eyeColorName, forKey: "maDeskAssistant.eyeColor")
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

struct VectorEyePose: Equatable {
    var centerX: CGFloat = 0
    var centerY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var angle: Double = 0
    var upperLid: CGFloat = 0
    var lowerLid: CGFloat = 0
    var spacing: CGFloat = 74

    static let neutral = VectorEyePose()

    static func glance(_ x: CGFloat, _ y: CGFloat = 0) -> VectorEyePose {
        VectorEyePose(centerX: x, centerY: y, angle: Double(x) * 0.15)
    }
}

struct CharacterView: View {
    let state: CharacterState
    var tint: Color
    var voiceLevel: Double
    var onTap: () -> Void

    @State private var pose = VectorEyePose.neutral
    @State private var hovering = false
    @State private var pulse = false

    private var glow: Color {
        switch state {
        case .error: return .red
        case .alert: return .yellow
        case .thinking: return .orange
        case .sleeping: return tint.opacity(0.55)
        default: return tint
        }
    }

    var body: some View {
        HStack(spacing: pose.spacing) {
            vectorEye(side: -1)
            vectorEye(side: 1)
        }
        .frame(width: 280, height: 150)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: pose)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovering = true
                let dx = max(-1, min(1, (point.x - 140) / 140))
                let dy = max(-1, min(1, (point.y - 75) / 75))
                var look = pose
                look.centerX = dx * 22
                look.centerY = dy * 14
                look.angle = Double(dx) * 6
                pose = look
            case .ended:
                hovering = false
                if state != .thinking { pose = expressionPose }
            }
        }
        .onTapGesture {
            pose = VectorEyePose(scaleX: 1.05, scaleY: 1.12, angle: 0, upperLid: 0.05, spacing: 58)
            onTap()
        }
        .task(id: state) {
            pulse.toggle()
            guard state != .sleeping else {
                pose = VectorEyePose(scaleY: 0.16, spacing: 74)
                return
            }
            if state == .thinking {
                while !Task.isCancelled {
                    pose = VectorEyePose.glance(pose.centerX >= 0 ? -18 : 18, -4)
                    try? await Task.sleep(for: .milliseconds(700))
                }
                return
            }
            pose = expressionPose
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3.2...6.8)))
                if Task.isCancelled { continue }
                if state == .listening || state == .speaking { continue }
                await playIdle()
                if !hovering { pose = expressionPose }
            }
        }
    }

    private var expressionPose: VectorEyePose {
        switch state {
        case .happy:
            return VectorEyePose(scaleX: 1.04, scaleY: 1.08, spacing: 60)
        case .listening, .speaking:
            return VectorEyePose(scaleY: 1.1 + voiceLevel * 0.2, spacing: 62)
        case .alert, .error:
            return VectorEyePose(scaleX: 1.08, scaleY: 0.62, spacing: 80)
        default:
            let heard = CGFloat(min(max(voiceLevel, 0), 1))
            return VectorEyePose(scaleY: 1 + heard * 0.18, spacing: 74 - heard * 8)
        }
    }

    private func vectorEye(side: CGFloat) -> some View {
        let width = 82 * pose.scaleX
        let height = max(8, 84 * pose.scaleY)
        return Capsule()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.98), glow, glow.opacity(0.25)],
                    center: .center,
                    startRadius: 2,
                    endRadius: 70
                )
            )
            .frame(width: width, height: height)
            .rotationEffect(.degrees(pose.angle * side))
            .offset(x: pose.centerX, y: pose.centerY)
            .shadow(color: glow.opacity(0.85), radius: hovering ? 32 : 18 + voiceLevel * 20)
    }

    private func playIdle() async {
        let blink = Int.random(in: 0...4) < 3
        if blink {
            await blinkEyes()
            return
        }
        guard !hovering else { return }
        let clips: [VectorEyePose] = [
            .glance(-20),
            .glance(20, 2),
            .glance(CGFloat.random(in: -6...6), -14),
            VectorEyePose(scaleY: 0.45, spacing: 74),
            VectorEyePose(scaleX: 1.08, scaleY: 1.12, spacing: 52)
        ]
        pose = clips.randomElement() ?? .neutral
        try? await Task.sleep(for: .milliseconds(700))
    }

    private func blinkEyes() async {
        let open = hovering ? pose : expressionPose
        let shut = VectorEyePose(
            centerX: open.centerX,
            centerY: open.centerY,
            scaleX: open.scaleX,
            scaleY: 0.1,
            angle: open.angle,
            spacing: open.spacing
        )
        pose = shut
        try? await Task.sleep(for: .milliseconds(120))
        pose = open
        if Int.random(in: 0...9) == 0 {
            try? await Task.sleep(for: .milliseconds(180))
            pose = shut
            try? await Task.sleep(for: .milliseconds(110))
            pose = open
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
    @State private var speech = HomeSpeech()
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
                    CharacterView(
                        state: assistant.characterState,
                        tint: DeskEyeColor.color(named: assistant.eyeColorName),
                        voiceLevel: speech.isListening ? speech.inputLevel : 0
                    ) {
                        assistant.characterState = .listening
                        if let title = caseConversation.currentTitle {
                            assistant.responseText = "I'm looking at you. The open practice case is \(title). Say what to add, or ask a code question. A question does not change the note."
                        } else {
                            assistant.responseText = "I'm looking at you. No practice case is open, so a sentence will not be saved until you start a note or select a case."
                        }
                    }
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

                    if let item = currentChatCase {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Saving into \(item.title) · \(item.identifier)", systemImage: "doc.text.fill")
                                    .font(.headline)
                                Spacer()
                                Button("Undo") { undoCaseEdit() }
                                Button("Redo") { redoCaseEdit() }
                                Button("Clear") {
                                    caseConversation.reset()
                                    assistant.responseText = "No practice case is open. The next sentence will not be saved onto a note."
                                }
                            }
                            Text("ROS: \(PracticeTemplateStore.exportText(from: item.ros).isEmpty ? "nothing selected" : PracticeTemplateStore.exportText(from: item.ros))")
                            Text("Exam: \(PracticeTemplateStore.exportText(from: item.pe).isEmpty ? "nothing selected" : PracticeTemplateStore.exportText(from: item.pe))")
                            let cpt = PracticeCPTStore.load(item.cptDraftData).map(\.code).joined(separator: ", ")
                            Text("CPT: \(cpt.isEmpty ? "none" : cpt)")
                        }
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(14)
                        .frame(maxWidth: 790, alignment: .leading)
                        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("No practice case is open. Questions stay in the chat. Start a note before a symptom or CPT code can be saved.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: 790, alignment: .leading)
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
        .onChange(of: speech.isListening) { _, listening in
            assistant.characterState = listening ? .listening : (assistant.isSleeping ? .sleeping : .idle)
            if listening {
                assistant.responseText = "Microphone is on. Speak a fictional sentence. The words show above the text box, and the eyes grow when sound comes in."
            }
        }
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
            speech.stop()
            caseConversation.reset()
        }
    }

    private var currentChatCase: PracticeCase? {
        guard let id = caseConversation.currentCaseID else { return nil }
        return profileCases.first { $0.persistentModelID == id }
    }

    private func undoCaseEdit() {
        assistant.responseText = HomePracticeNoteController.CaseEditHistory.undo(in: profileCases, modelContext: modelContext)
        assistant.characterState = .idle
    }

    private func redoCaseEdit() {
        assistant.responseText = HomePracticeNoteController.CaseEditHistory.redo(in: profileCases, modelContext: modelContext)
        assistant.characterState = .idle
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
                ForEach(assistant.profiles) { profile in
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
        VStack(alignment: .leading, spacing: 8) {
            if speech.isListening || !speech.liveText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(speech.inputLevel > 0.08 ? Color.cyan : Color.white.opacity(0.35))
                            .frame(width: 10, height: 10)
                        Text(speech.isListening ? "Listening" : "Last thing heard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(speech.inputLevel > 0.08 ? "Hearing sound" : "Quiet")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(speech.liveText.isEmpty ? speech.status : speech.liveText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Capsule()
                        .fill(Color.cyan.opacity(0.85))
                        .frame(width: max(12, 280 * speech.inputLevel), height: 6)
                }
                .padding(12)
                .frame(maxWidth: 790, alignment: .leading)
                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            commandButtons
        }
    }

    private var commandButtons: some View {
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
                speech.toggle { spoken in
                    assistant.commandText = spoken
                }
            } label: {
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
            }
            .buttonStyle(.bordered)
            .tint(speech.isListening ? .red : .cyan)
            .help(speech.status)

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
        let id = UUID()
        let profile = assistant.activeProfileID
        requestID = id
        isGenerating = true
        assistant.characterState = .thinking
        assistant.responseText = "Asking the on-device model. This does not change a practice case."
        generationTask = Task { @MainActor in
            defer {
                if requestID == id {
                    requestID = nil
                    isGenerating = false
                    generationTask = nil
                }
            }
            do {
                let answer = try await ai.reply(to: input)
                try Task.checkCancellation()
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = answer
                assistant.characterState = .happy
            } catch is CancellationError {
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = "On-device reply stopped. Nothing was saved to a practice case."
                assistant.characterState = .idle
            } catch {
                guard requestID == id, assistant.activeProfileID == profile else { return }
                assistant.responseText = """
                The on-device model could not answer: \(error.localizedDescription)

                Note, ICD-10, and CPT commands still work. Nothing was saved to a practice case.
                """
                assistant.characterState = .error
            }
        }
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

                let caseNote = caseConversation.currentTitle.map {
                    "\n\nThis search did not change the open case: \($0)."
                } ?? "\n\nNo practice case was changed."
                assistant.responseText = answer + caseNote
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
        case .lookupCPT(let term):
            assistant.responseText = PracticeCPTLibrary.lookupReply(for: term)
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
