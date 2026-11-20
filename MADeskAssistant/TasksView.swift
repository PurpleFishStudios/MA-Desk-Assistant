import SwiftUI

struct TasksView: View {
    @Bindable var assistant: AssistantViewModel
    @State private var newTaskTitle = ""
    @State private var isSelectingTasks = false
    @State private var selectedTaskIDs = Set<UUID>()
    @State private var pendingTaskDeletionIDs = Set<UUID>()
    @State private var showTaskDeleteConfirmation = false

    private var incompleteTasks: [DeskTask] {
        assistant.tasks.filter { !$0.isComplete }
    }

    private var completedTasks: [DeskTask] {
        assistant.tasks.filter { $0.isComplete }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            addTaskBar
            taskSelectionControls
            taskList
            Spacer(minLength: 0)
        }
        .padding(32)
        .navigationTitle("Tasks")
        .confirmationDialog(
            "Permanently delete \(pendingTaskDeletionIDs.count) task\(pendingTaskDeletionIDs.count == 1 ? "" : "s")?",
            isPresented: $showTaskDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(pendingTaskDeletionIDs.count) Task\(pendingTaskDeletionIDs.count == 1 ? "" : "s")", role: .destructive) {
                deletePendingTasks()
            }
            Button("Cancel", role: .cancel) {
                pendingTaskDeletionIDs.removeAll()
            }
        } message: {
            Text("This cannot be undone. Both active and completed tasks can be deleted.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Task Workspace")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("\(incompleteTasks.count) task\(incompleteTasks.count == 1 ? "" : "s") remaining")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 38))
                .foregroundStyle(.cyan)
        }
    }

    private var addTaskBar: some View {
        HStack(spacing: 12) {
            TextField("Add a new task", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addTask() }

            Button {
                addTask()
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: 620)
    }

    private var taskSelectionControls: some View {
        HStack(spacing: 12) {
            Button(isSelectingTasks ? "Done Selecting" : "Select Multiple") {
                isSelectingTasks.toggle()
                if !isSelectingTasks { selectedTaskIDs.removeAll() }
            }
            .disabled(assistant.tasks.isEmpty)

            if isSelectingTasks {
                Button("Select All") {
                    selectedTaskIDs = Set(assistant.tasks.map(\.id))
                }
                Button("Delete Selected (\(selectedTaskIDs.count))", role: .destructive) {
                    requestTaskDeletion(selectedTaskIDs)
                }
                .disabled(selectedTaskIDs.isEmpty)
            }

            Spacer()
        }
        .frame(maxWidth: 760)
    }

    private var taskList: some View {
        List {
            Section("To Do") {
                if incompleteTasks.isEmpty {
                    Text("No unfinished tasks. Nice work.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(incompleteTasks) { task in
                        taskRow(task)
                    }
                }
            }

            Section("Completed") {
                if completedTasks.isEmpty {
                    Text("Completed tasks will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: 760)
    }

    private func taskRow(_ task: DeskTask) -> some View {
        HStack(spacing: 12) {
            if isSelectingTasks {
                Button {
                    toggleSelection(for: task.id)
                } label: {
                    Image(systemName: selectedTaskIDs.contains(task.id)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedTaskIDs.contains(task.id) ? .cyan : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(task.title) for deletion")
            }

            Button {
                if isSelectingTasks {
                    toggleSelection(for: task.id)
                } else {
                    assistant.toggleTask(task)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isComplete ? .green : .secondary)
                    Text(task.title)
                        .strikethrough(task.isComplete)
                        .foregroundStyle(task.isComplete ? .secondary : .primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Delete Task", role: .destructive) {
                    requestTaskDeletion([task.id])
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive) {
                    requestTaskDeletion([task.id])
                }
            }
        }
    }

    private func addTask() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        assistant.tasks.append(DeskTask(title: trimmedTitle))
        assistant.saveTasks()
        assistant.responseText = "Added task: \(trimmedTitle)."
        assistant.characterState = .happy
        newTaskTitle = ""
    }

    private func toggleSelection(for id: UUID) {
        if !selectedTaskIDs.insert(id).inserted {
            selectedTaskIDs.remove(id)
        }
    }

    private func requestTaskDeletion(_ ids: Set<UUID>) {
        let existingIDs = Set(assistant.tasks.map(\.id))
        let matchingIDs = ids.intersection(existingIDs)
        guard !matchingIDs.isEmpty else { return }
        pendingTaskDeletionIDs = matchingIDs
        showTaskDeleteConfirmation = true
    }

    private func deletePendingTasks() {
        let ids = pendingTaskDeletionIDs
        guard !ids.isEmpty else { return }
        assistant.tasks.removeAll { ids.contains($0.id) }
        assistant.saveTasks()
        selectedTaskIDs.subtract(ids)
        pendingTaskDeletionIDs.removeAll()
        assistant.responseText = "Deleted \(ids.count) task\(ids.count == 1 ? "" : "s")."
        assistant.characterState = .idle
        if assistant.tasks.isEmpty {
            isSelectingTasks = false
            selectedTaskIDs.removeAll()
        }
    }
}

#Preview {
    TasksView(assistant: AssistantViewModel())
}
