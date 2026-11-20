import SwiftUI
import SwiftData
import ICD10CM
import UniformTypeIdentifiers

// Fictional practice cases only; never enter real patient information.
@Model
final class PracticeCase {
    var identifier: String
    var title: String
    var reasonForVisit: String
    var hpi: String
    var ros: String
    var pe: String
    var assessment: String
    var plan: String
    var createdAt: Date
    var updatedAt: Date
    var ownerProfileID: String? = "guest"
    var cptDraftData: String = ""
    @Relationship(deleteRule: .cascade) var codeReferences: [PracticeCodeReference] = []

    init(identifier: String, title: String, ownerProfileID: String = "guest") {
        self.identifier = identifier
        self.title = title
        self.ownerProfileID = ownerProfileID
        self.reasonForVisit = ""
        self.hpi = ""
        self.ros = ""
        self.pe = ""
        self.assessment = ""
        self.plan = ""
        self.createdAt = .now
        self.updatedAt = .now
        self.codeReferences = []
    }
}

@Model
final class PracticeCodeReference {
    var code: String
    var descriptionText: String
    var fiscalYear: String
    var addedAt: Date

    init(code: String, descriptionText: String, fiscalYear: String = "FY2027") {
        self.code = code
        self.descriptionText = descriptionText
        self.fiscalYear = fiscalYear
        self.addedAt = .now
    }
}

private struct PracticeCaseDraft: Equatable {
    var identifier: String
    var title: String
    var reasonForVisit: String
    var hpi: String
    var ros: String
    var pe: String
    var assessment: String
    var plan: String

    init(_ item: PracticeCase) {
        identifier = item.identifier
        title = item.title
        reasonForVisit = item.reasonForVisit
        hpi = item.hpi
        ros = item.ros
        pe = item.pe
        assessment = item.assessment
        plan = item.plan
    }

    func apply(to item: PracticeCase) {
        item.identifier = identifier
        item.title = title
        item.reasonForVisit = reasonForVisit
        item.hpi = hpi
        item.ros = ros
        item.pe = pe
        item.assessment = assessment
        item.plan = plan
    }
}

struct PracticeCasesView: View {
    let activeProfileID: String
    let activeProfileName: String
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeCase.updatedAt, order: .reverse) private var cases: [PracticeCase]
    @State private var searchText = ""
    @State private var selectedCaseID: PersistentIdentifier?
    @State private var selectedForDeletion = Set<PersistentIdentifier>()
    @State private var isSelecting = false
    @State private var pendingDeletionIDs = Set<PersistentIdentifier>()
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private var normalizedProfileID: String {
        activeProfileID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var profileCases: [PracticeCase] {
        cases.filter {
            ($0.ownerProfileID ?? "guest").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedProfileID
        }
    }

    private var filteredCases: [PracticeCase] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !query.isEmpty else {
            return profileCases
        }

        return profileCases.filter { item in
            [
                item.identifier,
                item.title,
                item.reasonForVisit,
                item.hpi,
                PracticeTemplateStore.exportText(from: item.ros),
                PracticeTemplateStore.exportText(from: item.pe),
                item.cptDraftData,
                item.assessment,
                item.plan
            ]
            .contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var selectedCase: PracticeCase? {
        cases.first { $0.persistentModelID == selectedCaseID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Practice Cases")
                        .font(.headline)
                    Text("Profile: \(activeProfileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        addCase()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New fictional case")
                }

                TextField("Search fake ID or note text", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if !cases.isEmpty {
                    HStack {
                        Button(isSelecting ? "Done Selecting" : "Select Multiple") {
                            isSelecting.toggle()

                            if !isSelecting {
                                selectedForDeletion.removeAll()
                            }
                        }

                        if isSelecting {
                            Spacer()

                            Button("Select All Shown") {
                                selectedForDeletion.formUnion(
                                    filteredCases.map(\.persistentModelID)
                                )
                            }
                        }
                    }

                    if isSelecting {
                        HStack {
                            Button(
                                "Delete Selected (\(selectedForDeletion.count))",
                                role: .destructive
                            ) {
                                requestDeletion(selectedForDeletion)
                            }
                            .disabled(selectedForDeletion.isEmpty)

                            Spacer()

                            Button("Clear Selection") {
                                selectedForDeletion.removeAll()
                            }
                            .disabled(selectedForDeletion.isEmpty)
                        }
                    }
                }

                List {
                    ForEach(filteredCases) { item in
                        HStack(spacing: 10) {
                            if isSelecting {
                                Button {
                                    toggleSelection(item.persistentModelID)
                                } label: {
                                    Image(
                                        systemName: selectedForDeletion.contains(
                                            item.persistentModelID
                                        )
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                    )
                                    .foregroundStyle(
                                        selectedForDeletion.contains(
                                            item.persistentModelID
                                        )
                                        ? .cyan
                                        : .secondary
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "Select \(item.title) for deletion"
                                )
                            }

                            Button {
                                if isSelecting {
                                    toggleSelection(item.persistentModelID)
                                } else {
                                    selectedCaseID = item.persistentModelID
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        item.title.isEmpty
                                        ? "Untitled case"
                                        : item.title
                                    )
                                    .font(.headline)

                                    Text(
                                        item.identifier.isEmpty
                                        ? "No fake ID"
                                        : item.identifier
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    Text(item.updatedAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button(
                                "Delete Fictional Case",
                                role: .destructive
                            ) {
                                requestDeletion([item.persistentModelID])
                            }
                        }
                        .swipeActions(
                            edge: .trailing,
                            allowsFullSwipe: false
                        ) {
                            Button("Delete", role: .destructive) {
                                requestDeletion([item.persistentModelID])
                            }
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            .red.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                if profileCases.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(activeProfileName) has no fictional cases yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Create Fictional Case") {
                            addCase()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text(
                    "Fictional cases only. No real patient identifiers or notes."
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            .padding(16)
            .frame(minWidth: 230, idealWidth: 280, maxWidth: 320)

            Divider()

            if let item = selectedCase {
                PracticeCaseEditor(
                    item: item,
                    onSave: { draft in
                        saveCase(item, draft: draft)
                    },
                    onDelete: {
                        requestDeletion([item.persistentModelID])
                    }
                )
                .id(item.persistentModelID)
            } else {
                ContentUnavailableView(
                    "No Case Selected",
                    systemImage: "note.text",
                    description: Text(
                        "Choose a fictional case or create one with +."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "Permanently delete \(pendingDeletionIDs.count) fictional case\(pendingDeletionIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Delete \(pendingDeletionIDs.count) Case\(pendingDeletionIDs.count == 1 ? "" : "s")",
                role: .destructive
            ) {
                deletePendingCases()
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionIDs.removeAll()
            }
        } message: {
            Text(
                "This deletes the chosen fictional SOAP note\(pendingDeletionIDs.count == 1 ? "" : "s") and cannot be undone."
            )
        }
        .alert(
            "Could Not Save",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown storage error")
        }
    }

    private func addCase() {
        let item = PracticeCase(
            identifier: "DEMO-\(UUID().uuidString.prefix(8))",
            title: "New fictional case",
            ownerProfileID: normalizedProfileID
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
            selectedCaseID = item.persistentModelID
            searchText = ""
            isSelecting = false
            selectedForDeletion.removeAll()
            errorMessage = nil
        } catch {
            modelContext.rollback()
            errorMessage = "Save error: \(error.localizedDescription)"
            print("SwiftData Add Case Error: \(error)")
        }
    }
    
    private func saveCase(
        _ item: PracticeCase,
        draft: PracticeCaseDraft
    ) -> Bool {
        draft.apply(to: item)
        item.updatedAt = .now

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = "Draft was not saved: \(error.localizedDescription)"
            return false
        }
    }

    private func toggleSelection(_ id: PersistentIdentifier) {
        if !selectedForDeletion.insert(id).inserted {
            selectedForDeletion.remove(id)
        }
    }

    private func requestDeletion(_ ids: Set<PersistentIdentifier>) {
        let matching = ids.intersection(
            Set(cases.map(\.persistentModelID))
        )

        guard !matching.isEmpty else { return }

        pendingDeletionIDs = matching
        showDeleteConfirmation = true
    }

    private func deletePendingCases() {
        let ids = pendingDeletionIDs

        guard !ids.isEmpty else { return }

        let items = cases.filter { ids.contains($0.persistentModelID) }

        guard !items.isEmpty else {
            pendingDeletionIDs.removeAll()
            return
        }

        for item in items {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()

            if let selectedCaseID, ids.contains(selectedCaseID) {
                self.selectedCaseID = nil
            }

            selectedForDeletion.subtract(ids)
            pendingDeletionIDs.removeAll()

            if cases.count == items.count {
                isSelecting = false
                selectedForDeletion.removeAll()
            }
        } catch {
            modelContext.rollback()
            pendingDeletionIDs.removeAll()
            errorMessage = "Could not delete fictional cases: \(error.localizedDescription)"
        }
    }
}

private struct PracticeCaseEditor: View {
    @Environment(\.modelContext) private var modelContext

    let item: PracticeCase
    let onSave: (PracticeCaseDraft) -> Bool
    let onDelete: () -> Void

    @State private var draft: PracticeCaseDraft
    @State private var savedDraft: PracticeCaseDraft
    @State private var showPreview = false
    @State private var showDiscardConfirmation = false
    @State private var showCodePicker = false
    @State private var showCPTPicker = false
    @State private var codeError: String?
    @State private var pendingRemovalID: PersistentIdentifier?
    @State private var showRemoveConfirmation = false
    @State private var pdfDocument: PracticeNotePDFDocument?
    @State private var showingPDFExporter = false
    @State private var showingUnsavedPDFWarning = false
    @State private var pdfExportError: String?

    // Case assistant state
    @State private var assistantQuestion = ""
    @State private var assistantAnswer = ""
    @State private var showAssistantAnswer = false

    init(
        item: PracticeCase,
        onSave: @escaping (PracticeCaseDraft) -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete

        let initialDraft = PracticeCaseDraft(item)
        _draft = State(initialValue: initialDraft)
        _savedDraft = State(initialValue: initialDraft)
    }

    private var hasUnsavedChanges: Bool {
        draft != savedDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Fictional Encounter")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(
                    "Do not enter real patient names, MRNs, dates of birth, or clinical notes."
                )
                .font(.callout)
                .foregroundStyle(.orange)

                Text(
                    hasUnsavedChanges
                    ? "Unsaved changes"
                    : "All changes saved"
                )
                .font(.caption)
                .foregroundStyle(
                    hasUnsavedChanges
                    ? .orange
                    : .secondary
                )

                labeledField(
                    "Fake case identifier",
                    text: $draft.identifier
                )

                labeledField(
                    "Case title",
                    text: $draft.title
                )

                labeledField(
                    "Reason for visit",
                    text: $draft.reasonForVisit
                )

                editor(
                    "HPI — History of Present Illness",
                    text: $draft.hpi
                )

                PracticeTemplateEditor(
                    title: "ROS — Review of Systems",
                    kind: .ros,
                    stored: $draft.ros
                )

                PracticeTemplateEditor(
                    title: "PE — Physical Examination",
                    kind: .pe,
                    stored: $draft.pe
                )

                editor(
                    "Assessment",
                    text: $draft.assessment
                )

                editor(
                    "Plan",
                    text: $draft.plan
                )

                caseAssistant

                reviewChecklist

                codeReferencesSection

                cptReferencesSection

                HStack {
                    Button("Save Draft") {
                        if onSave(draft) {
                            savedDraft = draft
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)

                    Button("Discard Changes") {
                        showDiscardConfirmation = true
                    }
                    .disabled(!hasUnsavedChanges)

                    Button(
                        showPreview
                        ? "Hide Preview"
                        : "Preview Note"
                    ) {
                        showPreview.toggle()
                    }

                    Button("Export PDF") {
                        if hasUnsavedChanges {
                            showingUnsavedPDFWarning = true
                        } else {
                            preparePDFExport()
                        }
                    }

                    Button("Delete This Note", role: .destructive) {
                        onDelete()
                    }
                }

                if showPreview {
                    previewSection
                }
            }
            .frame(maxWidth: 850, alignment: .leading)
            .padding(28)
        }
        .sheet(isPresented: $showCodePicker) {
            PracticeCodePicker(
                existingCodes: Set(item.codeReferences.map(\.code))
            ) { code in
                attachCode(code)
            }
            .frame(minWidth: 900, minHeight: 680)
        }
        .sheet(isPresented: $showCPTPicker) {
            PracticeCPTPicker(
                existingCodes: Set(PracticeCPTStore.load(item.cptDraftData).map(\.code))
            ) { code in
                attachCPT(code)
            }
            .frame(minWidth: 760, minHeight: 560)
        }
        .alert(
            "Case Assistant",
            isPresented: $showAssistantAnswer
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(assistantAnswer)
        }
        .confirmationDialog(
            "Discard unsaved edits?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                draft = savedDraft
            }

            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(
                "The last saved version of this fictional note will remain unchanged."
            )
        }
        .confirmationDialog(
            "Remove this code reference?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Reference", role: .destructive) {
                removePendingReference()
            }

            Button("Cancel", role: .cancel) {
                pendingRemovalID = nil
            }
        } message: {
            Text("This removes the reference from this fictional case only.")
        }
        .alert(
            "Could Not Update References",
            isPresented: Binding(
                get: { codeError != nil },
                set: { if !$0 { codeError = nil } }
            )
        ) {
            Button("OK") {
                codeError = nil
            }
        } message: {
            Text(codeError ?? "Unknown error")
        }
        .confirmationDialog(
            "Export the last saved version?",
            isPresented: $showingUnsavedPDFWarning,
            titleVisibility: .visible
        ) {
            Button("Export Last Saved Version") {
                preparePDFExport()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "You have unsaved edits. The PDF will contain the last saved SOAP text, not the edits currently on screen."
            )
        }
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Fictional_Practice_SOAP_Note"
        ) { result in
            if case .failure(let error) = result {
                pdfExportError = error.localizedDescription
            }

            pdfDocument = nil
        }
        .alert(
            "Could Not Export PDF",
            isPresented: Binding(
                get: { pdfExportError != nil },
                set: { if !$0 { pdfExportError = nil } }
            )
        ) {
            Button("OK") {
                pdfExportError = nil
            }
        } message: {
            Text(pdfExportError ?? "Unknown export error")
        }
    }

    private var caseAssistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Case Assistant",
                    systemImage: "sparkles"
                )
                .font(.headline)

                Spacer()

                Text("Saved fictional note only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(
                "Recall or summarize only information saved in this fictional practice case. This tool does not diagnose, assign codes, prescribe, or create clinical facts."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if hasUnsavedChanges {
                Text(
                    "Save Draft first to ask about the most recent changes. Answers use the last saved note."
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            TextField(
                "Ask: What diagnosis did I document? What is the plan?",
                text: $assistantQuestion
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                answerCaseQuestion()
            }

            HStack {
                Button("Ask This Case") {
                    answerCaseQuestion()
                }
                .buttonStyle(.borderedProminent)

                Button("What diagnosis did I document?") {
                    assistantQuestion = "What diagnosis did I document?"
                    answerCaseQuestion()
                }

                Button("What is the plan?") {
                    assistantQuestion = "What is the plan?"
                    answerCaseQuestion()
                }

                Button("Summarize Case") {
                    assistantQuestion = "Summarize this case"
                    answerCaseQuestion()
                }

                Button("Review Documentation") {
                    assistantAnswer = documentationReview()
                    showAssistantAnswer = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var codeReferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ICD-10-CM references (FY2027)")
                    .font(.headline)

                Spacer()

                Button("Look Up Code") {
                    showCodePicker = true
                }
            }

            Text(
                "References attached from chat or the lookup, for a fictional case. Not an assigned diagnosis or billing code. Review each one before you submit."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if item.codeReferences.isEmpty {
                Text("No references attached.")
                    .foregroundStyle(.secondary)
            }

            ForEach(
                item.codeReferences.sorted { $0.addedAt < $1.addedAt }
            ) { reference in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            "\(reference.code) — \(reference.descriptionText)"
                        )

                        Text(reference.fiscalYear)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Remove", role: .destructive) {
                        pendingRemovalID = reference.persistentModelID
                        showRemoveConfirmation = true
                    }
                }
            }
        }
        .padding(12)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var cptReferencesSection: some View {
        let entries = PracticeCPTStore.load(item.cptDraftData)
        let icdCodes = item.codeReferences.map(\.code)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CPT practice codes")
                    .font(.headline)
                Spacer()
                Button("Look Up CPT") {
                    showCPTPicker = true
                }
            }

            Text("Teaching subset only. Link each CPT code to the ICD-10-CM references already on this fictional case. This is not a final code pair.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("No CPT codes attached.")
                    .foregroundStyle(.secondary)
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(PracticeCPTStore.displayLine(entry))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            removeCPT(entry.id)
                        }
                    }

                    if icdCodes.isEmpty {
                        Text("Attach an ICD-10-CM reference above, then you can link it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Linked ICD-10-CM")
                            .font(.caption.weight(.semibold))
                        FlowCPTLinks(
                            codes: icdCodes,
                            selected: Set(entry.linkedICDCodes)
                        ) { code in
                            toggleCPTLink(code, entryID: entry.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fictional Practice SOAP Note")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("Practice draft only — not a patient record")
                .font(.callout)
                .foregroundStyle(.orange)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Case title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(previewValue(draft.title))
                    .font(.title3.weight(.semibold))

                Text(
                    "Fake case identifier: \(previewValue(draft.identifier))"
                )
                .font(.callout)

                Text(
                    "Last saved: \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if hasUnsavedChanges {
                Text(
                    "Unsaved edits are shown in this preview. Save Draft before relying on the saved version."
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            Divider()

            preview("Reason for Visit", draft.reasonForVisit)
            preview("HPI — History of Present Illness", draft.hpi)
            preview("ROS — Review of Systems", PracticeTemplateStore.exportText(from: draft.ros))
            preview("PE — Physical Examination", PracticeTemplateStore.exportText(from: draft.pe))
            preview("Assessment", draft.assessment)
            preview("Plan", draft.plan)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("ICD-10-CM References for Review")
                    .font(.headline)

                if item.codeReferences.isEmpty {
                    Text("None selected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        item.codeReferences.sorted {
                            $0.addedAt < $1.addedAt
                        }
                    ) { reference in
                        Text(
                            "\(reference.code) — \(reference.descriptionText) (\(reference.fiscalYear))"
                        )
                        .textSelection(.enabled)
                    }
                }

                Text(
                    "References are for review. They are not assigned diagnoses or final billing codes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("CPT practice codes")
                    .font(.headline)
                    .padding(.top, 8)

                let cptEntries = PracticeCPTStore.load(item.cptDraftData)
                if cptEntries.isEmpty {
                    Text("None selected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cptEntries) { entry in
                        Text(PracticeCPTStore.displayLine(entry))
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            Text(
                "Fictional practice case only — not a patient record, diagnosis, or billing document."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func answerCaseQuestion() {
        let question = assistantQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !question.isEmpty else {
            assistantAnswer = "Type a question about this saved fictional practice case."
            showAssistantAnswer = true
            return
        }

        let sourceNote = """
        Source: \(savedValue(item.title, fallback: "Untitled fictional case")) → saved fictional SOAP note.
        This is recall from the saved practice note, not a new diagnosis, code assignment, or treatment recommendation.
        """

        if containsAny(
            question,
            words: [
                "diagnosis",
                "diagnoses",
                "assessment",
                "assess"
            ]
        ) {
            assistantAnswer = """
            Documented assessment:
            \(savedValue(item.assessment, fallback: "No assessment was entered in the saved note."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "plan",
                "treatment",
                "next step",
                "next steps"
            ]
        ) {
            assistantAnswer = """
            Documented plan:
            \(savedValue(item.plan, fallback: "No plan was entered in the saved note."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "summary",
                "summarize",
                "summarise",
                "overview"
            ]
        ) {
            assistantAnswer = caseSummary()
        } else if containsAny(
            question,
            words: [
                "hpi",
                "history",
                "present illness"
            ]
        ) {
            assistantAnswer = """
            Saved HPI:
            \(savedValue(item.hpi, fallback: "No HPI was entered in the saved note."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "ros",
                "review of systems",
                "systems"
            ]
        ) {
            assistantAnswer = """
            Saved ROS:
            \(savedValue(PracticeTemplateStore.exportText(from: item.ros), fallback: "No ROS findings are selected."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "physical",
                "exam",
                "pe",
                "examination"
            ]
        ) {
            assistantAnswer = """
            Saved physical exam:
            \(savedValue(PracticeTemplateStore.exportText(from: item.pe), fallback: "No physical-exam findings are selected."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "reason",
                "visit",
                "chief complaint"
            ]
        ) {
            assistantAnswer = """
            Saved reason for visit:
            \(savedValue(item.reasonForVisit, fallback: "No reason for visit was entered in the saved note."))

            \(sourceNote)
            """
        } else if containsAny(
            question,
            words: [
                "code",
                "icd",
                "icd-10"
            ]
        ) {
            assistantAnswer = codeReferenceAnswer(sourceNote: sourceNote)
        } else {
            assistantAnswer = """
            I can recall only saved information from this fictional case.

            Try:
            • What diagnosis did I document?
            • What is the plan?
            • Summarize this case.
            • What did I write in the HPI?
            • Which ICD-10-CM references did I attach?

            \(sourceNote)
            """
        }

        showAssistantAnswer = true
    }

    private func caseSummary() -> String {
        """
        Saved fictional case summary

        Reason for visit:
        \(savedValue(item.reasonForVisit, fallback: "Not entered"))

        HPI:
        \(savedValue(item.hpi, fallback: "Not entered"))

        ROS:
        \(savedValue(PracticeTemplateStore.exportText(from: item.ros), fallback: "Not entered"))

        Physical exam:
        \(savedValue(PracticeTemplateStore.exportText(from: item.pe), fallback: "Not entered"))

        Assessment:
        \(savedValue(item.assessment, fallback: "Not entered"))

        Plan:
        \(savedValue(item.plan, fallback: "Not entered"))

        Source: \(savedValue(item.title, fallback: "Untitled fictional case")) → saved fictional SOAP note.
        This summary only combines text saved by the student. It does not add clinical facts, diagnose, assign codes, or recommend treatment.
        """
    }

    private func codeReferenceAnswer(sourceNote: String) -> String {
        guard !item.codeReferences.isEmpty else {
            return """
            No ICD-10-CM references are attached to this saved fictional case.

            \(sourceNote)
            """
        }

        let references = item.codeReferences
            .sorted { $0.addedAt < $1.addedAt }
            .map {
                "• \($0.code) — \($0.descriptionText) (\($0.fiscalYear))"
            }
            .joined(separator: "\n")

        return """
        Attached ICD-10-CM references:

        \(references)

        \(sourceNote)
        These are references for review only—not assigned diagnoses or final billing codes.
        """
    }

    private func containsAny(
        _ text: String,
        words: [String]
    ) -> Bool {
        words.contains { text.contains($0) }
    }

    private func savedValue(
        _ value: String,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? fallback : trimmed
    }
    private func documentationReview() -> String {
        let sections: [(String, String)] = [
            ("Reason for visit", item.reasonForVisit),
            ("HPI", item.hpi),
            ("ROS", item.ros),
            ("PE", item.pe),
            ("Assessment", item.assessment),
            ("Plan", item.plan)
        ]

        let statusLines = sections.map { label, value in
            let isEmpty = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            return "• \(label): \(isEmpty ? "Not entered" : "Entered")"
        }
        .joined(separator: "\n")

        var prompts: [String] = []

        if item.reasonForVisit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            prompts.append("Add the fictional reason for visit.")
        }

        if item.hpi
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            prompts.append("Add only assignment-supported HPI details, such as onset, duration, location, or associated symptoms.")
        }

        if PracticeTemplateStore.isBlank(item.ros) {
            prompts.append("Select the ROS findings supported by this fictional assignment.")
        }

        if PracticeTemplateStore.isBlank(item.pe) {
            prompts.append("Select only physical-exam findings the fictional assignment supports.")
        }

        if item.assessment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            prompts.append("Add the assessment documented for this fictional practice case.")
        }

        if item.plan
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            prompts.append("Add the fictional plan required by the assignment, if applicable.")
        }

        if !item.hpi
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            prompts.append("For practice, check whether the HPI includes onset/duration, location or distribution, appearance, and relevant associated symptoms.")
        }

        if !PracticeTemplateStore.isBlank(item.pe) {
            prompts.append("For practice, check whether the selected PE findings are only the ones the fictional assignment supports.")
        }

        let promptText = prompts.isEmpty
            ? "• All six SOAP sections are entered. Review wording for accuracy, specificity, and support from the fictional assignment."
            : prompts.map { "• \($0)" }.joined(separator: "\n")

        return """
        Documentation review — saved fictional case

        \(statusLines)

        Practice prompts:
        \(promptText)

        Source: \(savedValue(item.title, fallback: "Untitled fictional case")) → saved fictional SOAP note.
        This checklist does not diagnose, assign codes, recommend treatment, or create ROS/PE findings. Enter only information supported by the fictional assignment.
        """
    }
    private func preparePDFExport() {
        do {
            let snapshot = PracticeNotePDFSnapshot(case: item)
            pdfDocument = try PracticeNotePDFExporter.makeDocument(
                from: snapshot
            )
            showingPDFExporter = true
        } catch {
            pdfExportError = error.localizedDescription
        }
    }

    private func attachCode(_ code: ICD10Code) {
        guard code.isBillable else { return }

        guard !item.codeReferences.contains(
            where: {
                $0.code == code.code && $0.fiscalYear == "FY2027"
            }
        ) else {
            showCodePicker = false
            return
        }

        let reference = PracticeCodeReference(
            code: code.code,
            descriptionText: code.longDescription
        )

        item.codeReferences.append(reference)

        do {
            try modelContext.save()
            showCodePicker = false
        } catch {
            modelContext.rollback()
            codeError = "Reference was not attached: \(error.localizedDescription)"
        }
    }

    private func attachCPT(_ code: PracticeCPTCode) {
        var entries = PracticeCPTStore.load(item.cptDraftData)
        guard !entries.contains(where: { $0.code == code.code }) else {
            showCPTPicker = false
            return
        }
        entries.append(PracticeCPTEntry(code: code.code, descriptionText: code.label))
        item.cptDraftData = PracticeCPTStore.save(entries)
        item.updatedAt = .now
        do {
            try modelContext.save()
            showCPTPicker = false
        } catch {
            modelContext.rollback()
            codeError = "CPT code was not attached: \(error.localizedDescription)"
        }
    }

    private func removeCPT(_ id: UUID) {
        var entries = PracticeCPTStore.load(item.cptDraftData)
        entries.removeAll { $0.id == id }
        item.cptDraftData = PracticeCPTStore.save(entries)
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            codeError = "CPT code was not removed: \(error.localizedDescription)"
        }
    }

    private func toggleCPTLink(_ code: String, entryID: UUID) {
        var entries = PracticeCPTStore.load(item.cptDraftData)
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        if let linkIndex = entries[index].linkedICDCodes.firstIndex(of: code) {
            entries[index].linkedICDCodes.remove(at: linkIndex)
        } else {
            entries[index].linkedICDCodes.append(code)
        }
        item.cptDraftData = PracticeCPTStore.save(entries)
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            codeError = "The ICD-10 link was not saved: \(error.localizedDescription)"
        }
    }

    private func removePendingReference() {
        guard let pendingRemovalID,
              let reference = item.codeReferences.first(
                where: {
                    $0.persistentModelID == pendingRemovalID
                }
              ) else {
            self.pendingRemovalID = nil
            return
        }

        let removedCode = reference.code
        modelContext.delete(reference)
        var cptEntries = PracticeCPTStore.load(item.cptDraftData)
        for index in cptEntries.indices {
            cptEntries[index].linkedICDCodes.removeAll { $0 == removedCode }
        }
        item.cptDraftData = PracticeCPTStore.save(cptEntries)

        do {
            try modelContext.save()
            self.pendingRemovalID = nil
        } catch {
            modelContext.rollback()
            self.pendingRemovalID = nil
            codeError = "Reference was not removed: \(error.localizedDescription)"
        }
    }

    private var reviewChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Draft review")
                .font(.headline)

            Text(
                hasUnsavedChanges
                ? "Unsaved edits: save the draft before relying on the saved note."
                : "The displayed SOAP text matches the last saved draft."
            )
            .font(.callout)
            .foregroundStyle(
                hasUnsavedChanges
                ? .orange
                : .secondary
            )

            reviewRow("Reason for visit", draft.reasonForVisit)
            reviewRow("HPI", draft.hpi)
            reviewRow("ROS", PracticeTemplateStore.exportText(from: draft.ros))
            reviewRow("PE", PracticeTemplateStore.exportText(from: draft.pe))
            reviewRow("Assessment", draft.assessment)
            reviewRow("Plan", draft.plan)

            Text(
                "ICD-10-CM entries are references for review, not assigned diagnoses."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func reviewRow(
        _ label: String,
        _ value: String
    ) -> some View {
        let isEmpty = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return HStack {
            Image(
                systemName: isEmpty
                ? "circle.dashed"
                : "checkmark.circle.fill"
            )
            .foregroundStyle(isEmpty ? .orange : .green)

            Text(label)

            Spacer()

            Text(isEmpty ? "Not entered" : "Entered")
                .foregroundStyle(isEmpty ? .orange : .secondary)
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func editor(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            TextEditor(text: text)
                .frame(minHeight: 105)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray.opacity(0.35))
                )
        }
    }

    private func preview(
        _ title: String,
        _ text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)

            Text(previewValue(text))
                .textSelection(.enabled)
        }
    }

    private func previewValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? "Not entered" : trimmed
    }
}

private struct PracticeCodePicker: View {
    @Environment(\.dismiss) private var dismiss

    let existingCodes: Set<String>
    let onAttach: (ICD10Code) -> Void

    @State private var store: ICD10Store?
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var selectedCode: String?
    @State private var detail: CodeDetail?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add a code reference")
                    .font(.title2.bold())

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            Text(
                "FY2027. Fictional cases only. Select a billable result after reviewing its notes. This does not assign a diagnosis."
            )
            .foregroundStyle(.orange)

            TextField("Search code or term", text: $query)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .top, spacing: 16) {
                List {
                    ForEach(hits, id: \.code.code) { hit in
                        Button {
                            selectedCode = hit.code.code
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.code.code)
                                    .font(.headline)

                                Text(hit.code.longDescription)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )

                                if hit.code.requiresMoreCharacters
                                    || hit.isIncomplete {
                                    Text("More specificity required")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedCode == hit.code.code
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                        )
                    }
                }
                .frame(minWidth: 300, idealWidth: 360)

                Divider()

                ScrollView {
                    if let detail {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                "\(detail.code.code) — \(detail.code.longDescription)"
                            )
                            .font(.title3.bold())

                            if detail.requiresMoreCharacters {
                                Text(
                                    "Header: more characters required. Choose a more specific code."
                                )
                                .foregroundStyle(.orange)
                            } else {
                                Text("Billable; still requires coding review.")
                            }

                            if !detail.children.isEmpty {
                                Text("More specific children")
                                    .font(.headline)

                                ForEach(
                                    detail.children,
                                    id: \.code
                                ) { child in
                                    Button(
                                        "\(child.code) — \(child.longDescription)"
                                    ) {
                                        selectedCode = child.code
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                            }

                            Divider()

                            Text("Instructional notes")
                                .font(.headline)

                            if detail.notes.isEmpty {
                                Text("No notes returned.")
                            } else {
                                ForEach(
                                    Array(detail.notes.enumerated()),
                                    id: \.offset
                                ) { _, note in
                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(note.kind.rawValue)
                                            .font(.headline)
                                            .foregroundStyle(
                                                note.kind == .excludes1
                                                ? .orange
                                                : .primary
                                            )

                                        Text(note.text)

                                        Text(
                                            "Source: \(noteSource(note.source))\(note.isInherited ? " (inherited)" : "")"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(8)
                                    .background(
                                        .quaternary.opacity(0.5),
                                        in: RoundedRectangle(
                                            cornerRadius: 8
                                        )
                                    )
                                }
                            }

                            Button("Add Reference to This Case") {
                                onAttach(detail.code)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                detail.requiresMoreCharacters
                                || existingCodes.contains(detail.code.code)
                            )

                            if existingCodes.contains(detail.code.code) {
                                Text(
                                    "This case already has this reference."
                                )
                                .font(.caption)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    } else {
                        Text(
                            "Select a result to inspect its notes before adding."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .task {
            guard store == nil else { return }

            do {
                store = try ICD10Store()
            } catch {
                errorMessage = "Database could not open: \(error.localizedDescription)"
            }
        }
        .task(id: query) {
            guard let store else { return }

            let text = query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !text.isEmpty else {
                store.cancelInFlightSearches()
                hits = []
                selectedCode = nil
                detail = nil
                return
            }

            hits = []
            detail = nil
            selectedCode = nil

            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                try Task.checkCancellation()

                let found = try await store.searchAsync(
                    text,
                    limit: 25,
                    options: SearchOptions(useSynonyms: false)
                )

                try Task.checkCancellation()

                hits = found
                errorMessage = found.isEmpty
                    ? "No results for this term or code."
                    : nil
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .task(id: selectedCode) {
            guard let store, let selectedCode else {
                detail = nil
                return
            }

            detail = nil

            do {
                let found = try store.lookup(selectedCode)
                try Task.checkCancellation()
                detail = found
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func noteSource(_ source: NoteSource) -> String {
        switch source {
        case .code(let value):
            return "code \(value)"
        case .section(let value):
            return "section \(value)"
        case .chapter(let value):
            return "chapter \(value)"
        }
    }
}
