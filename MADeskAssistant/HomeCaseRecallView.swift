import SwiftUI
import SwiftData

@MainActor
struct HomeCaseRecallView: View {
    let activeProfileID: String
    let onAnswer: (String) -> Void
    var onOpen: (PracticeCase) -> Void = { _ in }

    @Query(sort: \PracticeCase.updatedAt, order: .reverse)
    private var allCases: [PracticeCase]

    @State private var selectedID: PersistentIdentifier?

    private var profileCases: [PracticeCase] {
        let profileID = activeProfileID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !profileID.isEmpty else {
            return []
        }

        return allCases.filter { item in
            guard let ownerID = item.ownerProfileID else {
                return false
            }

            return ownerID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == profileID
        }
    }

    private var visibleIDs: [PersistentIdentifier] {
        profileCases.map(\.persistentModelID)
    }

    private var selectedCase: PracticeCase? {
        profileCases.first {
            $0.persistentModelID == selectedID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Saved fictional case",
                systemImage: "doc.text.magnifyingglass"
            )
            .font(.headline)

            if profileCases.isEmpty {
                Text(
                    "No owned fictional cases available for this profile."
                )
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
            } else {
                casePicker
                recallButtons
            }

            Text(
                """
                Exact saved text only. These buttons do not \
                use AI or change your note.
                """
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: 790, alignment: .leading)
        .background(
            .white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .onChange(of: activeProfileID) { _, _ in
            selectedID = nil

            onAnswer(
                "Profile changed. Select a fictional case to review."
            )
        }
        .onChange(of: selectedID) { _, newID in
            if newID != nil, let item = selectedCase {
                onOpen(item)
                onAnswer("Opened \(item.title) for this chat. Questions about this note use it and do not save changes.")
            } else {
                onAnswer(
                    "No case selected. Choose a fictional case to review."
                )
            }
        }
        .onChange(of: visibleIDs) { _, ids in
            guard let currentID = selectedID else {
                return
            }

            if !ids.contains(currentID) {
                selectedID = nil

                onAnswer(
                    """
                    The selected case is no longer available. \
                    Select another fictional case.
                    """
                )
            }
        }
    }

    private var casePicker: some View {
        Picker("Case", selection: $selectedID) {
            Text("Choose a fictional case")
                .tag(Optional<PersistentIdentifier>.none)

            ForEach(
                profileCases,
                id: \.persistentModelID
            ) { item in
                Text(
                    "\(savedValue(item.title)) · \(savedValue(item.identifier))"
                )
                .tag(Optional(item.persistentModelID))
            }
        }
        .pickerStyle(.menu)
    }

    private var recallButtons: some View {
        HStack(spacing: 10) {
            Button("Saved Assessment") {
                showAssessment()
            }

            Button("Saved Plan") {
                showPlan()
            }

            Button("Saved SOAP Text") {
                showSOAP()
            }
        }
        .buttonStyle(.bordered)
        .disabled(selectedCase == nil)
    }

    private func savedValue(_ text: String) -> String {
        if text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return "Not entered"
        }

        return text
    }

    private func source(
        for item: PracticeCase,
        section: String
    ) -> String {
        """
        Source: \(savedValue(item.title)) · \(savedValue(item.identifier))
        Section: \(section)
        Saved: \(item.updatedAt.formatted())

        Fictional practice note — exact recall, not a new \
        diagnosis or treatment recommendation.
        """
    }

    private func showAssessment() {
        guard let item = selectedCase else {
            return
        }

        onAnswer(
            """
            Saved Assessment:
            \(savedValue(item.assessment))

            \(source(for: item, section: "Assessment"))
            """
        )
    }

    private func showPlan() {
        guard let item = selectedCase else {
            return
        }

        onAnswer(
            """
            Saved Plan:
            \(savedValue(item.plan))

            \(source(for: item, section: "Plan"))
            """
        )
    }

    private func showSOAP() {
        guard let item = selectedCase else {
            return
        }

        let sections: [(String, String)] = [
            ("Reason for visit", item.reasonForVisit),
            ("HPI", item.hpi),
            ("ROS", item.ros),
            ("PE", item.pe),
            ("Assessment", item.assessment),
            ("Plan", item.plan)
        ]

        let text = sections.map { section in
            "\(section.0):\n\(savedValue(section.1))"
        }
        .joined(separator: "\n\n")

        onAnswer(
            """
            \(text)

            \(source(for: item, section: "Saved SOAP fields"))
            """
        )
    }
}
