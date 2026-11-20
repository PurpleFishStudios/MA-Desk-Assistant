//
//  PracticeTemplateEditor.swift
//  MADeskAssistant
//

import SwiftUI

struct PracticeTemplateEditor: View {
    let title: String
    let kind: PracticeTemplateKind
    @Binding var stored: String
    @State private var editingID: String?
    @State private var lastTapID: String?
    @State private var lastTapTime: Date?
    @State private var openSystems: Set<String> = []

    private var document: PracticeTemplateDocument {
        if let decoded = PracticeTemplateStore.decode(stored) {
            return decoded
        }
        return .empty
    }

    private var legacyText: String {
        guard PracticeTemplateStore.decode(stored) == nil else { return "" }
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("All Normal") { selectAllNormals() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Self.accent)
                Button("Clear") { clearAll() }
                    .buttonStyle(.borderless)
            }

            Text("Sections start closed so the note is shorter. Open one to click buttons. Double-click a button to type a note.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Expand sections") {
                    openSystems = Set(PracticeTemplateLibrary.systems(kind))
                }
                Button("Collapse sections") { openSystems.removeAll() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(previewLine)
                .font(.callout)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            if !legacyText.isEmpty {
                Text("Earlier typed note")
                    .font(.caption.weight(.semibold))
                Text(legacyText)
                    .font(.caption)
                    .textSelection(.enabled)
                Button("Move typed note into Other findings") {
                    var doc = document
                    doc.extraNote = legacyText
                    write(doc)
                }
                .buttonStyle(.bordered)
            }

            ForEach(PracticeTemplateLibrary.systems(kind), id: \.self) { system in
                DisclosureGroup(isExpanded: expanded(system)) {
                    systemBlock(system)
                } label: {
                    Text(systemTitle(system))
                        .font(.subheadline.weight(.semibold))
                }
            }

            if legacyText.isEmpty {
                Text("Other findings")
                    .font(.subheadline.weight(.semibold))
                TextField("Anything not on a button", text: extraNoteBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func expanded(_ system: String) -> Binding<Bool> {
        Binding(
            get: { openSystems.contains(system) },
            set: { isOpen in
                if isOpen { openSystems.insert(system) } else { openSystems.remove(system) }
            }
        )
    }

    private func systemTitle(_ system: String) -> String {
        let count = document.selections.filter {
            PracticeTemplateLibrary.finding(id: $0.id)?.system == system
        }.count
        return count == 0 ? system : "\(system) (\(count))"
    }

    private func systemBlock(_ system: String) -> some View {
        let rows = PracticeTemplateLibrary.findings(kind, system: system)
        let normals = rows.filter(\.isNormal)
        let others = rows.filter { !$0.isNormal }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(system)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("All Normal") { selectNormals(in: system) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Self.accent)
                Button("Clear") { clear(system) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Self.accent.opacity(0.85))
            }

            if !normals.isEmpty {
                chipWrap(normals)
            }
            if !others.isEmpty {
                chipWrap(others)
            }
        }
    }

    private func chipWrap(_ findings: [PracticeFinding]) -> some View {
        ChipFlow(spacing: 6) {
            ForEach(findings) { finding in
                chip(finding)
            }
        }
    }

    private func chip(_ finding: PracticeFinding) -> some View {
        let selected = document.selections.first { $0.id == finding.id }
        let isOn = selected != nil
        return Button {
            handleTap(finding.id)
        } label: {
            Text(chipTitle(finding, detail: selected?.detail ?? ""))
                .font(.callout.weight(isOn ? .semibold : .regular))
                .foregroundStyle(chipText(finding, selected: isOn))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chipColor(finding, selected: isOn), in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(chipBorder(finding, selected: isOn), lineWidth: isOn ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(isOn ? "Selected. Double-click to type a note." : "Click to select. Double-click to select and type a note.")
        .popover(isPresented: notePresented(finding.id)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(finding.label)
                    .font(.headline)
                TextField("Note, such as R arm or mild", text: detailBinding(for: finding.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                HStack {
                    Spacer()
                    Button("Done") { editingID = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }

    private func chipTitle(_ finding: PracticeFinding, detail: String) -> String {
        let clean = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? finding.label : "\(finding.label) (\(clean))"
    }

    private static let accent = Color(red: 0.35, green: 0.78, blue: 1.0)
    private static let navy = Color(red: 0.08, green: 0.14, blue: 0.24)

    private func chipColor(_ finding: PracticeFinding, selected: Bool) -> Color {
        if selected {
            return finding.isNormal ? Self.accent : Color(red: 0.16, green: 0.42, blue: 0.72)
        }
        return finding.isNormal ? Self.navy : Color(red: 0.11, green: 0.13, blue: 0.18)
    }

    private func chipText(_ finding: PracticeFinding, selected: Bool) -> Color {
        if selected {
            return finding.isNormal ? Self.navy : .white
        }
        return Color(red: 0.78, green: 0.88, blue: 0.96)
    }

    private func chipBorder(_ finding: PracticeFinding, selected: Bool) -> Color {
        if selected {
            return Self.accent
        }
        return finding.isNormal
            ? Self.accent.opacity(0.55)
            : Color.white.opacity(0.22)
    }

    private func notePresented(_ id: String) -> Binding<Bool> {
        Binding(
            get: { editingID == id },
            set: { isPresented in
                if !isPresented, editingID == id { editingID = nil }
            }
        )
    }

    private var previewLine: String {
        let text = PracticeTemplateStore.exportText(from: stored)
        return text.isEmpty ? "Nothing selected yet." : text
    }

    private var extraNoteBinding: Binding<String> {
        Binding(
            get: { document.extraNote },
            set: { newValue in
                var doc = PracticeTemplateStore.decode(stored) ?? .empty
                doc.extraNote = newValue
                write(doc)
            }
        )
    }

    private func detailBinding(for id: String) -> Binding<String> {
        Binding(
            get: { document.selections.first { $0.id == id }?.detail ?? "" },
            set: { setDetail($0, for: id) }
        )
    }

    private func baseDocument() -> PracticeTemplateDocument {
        if let decoded = PracticeTemplateStore.decode(stored) {
            return decoded
        }
        return PracticeTemplateDocument(selections: [], extraNote: legacyText)
    }

    private func write(_ document: PracticeTemplateDocument) {
        if document.selections.isEmpty && document.extraNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stored = ""
        } else {
            stored = PracticeTemplateStore.encode(document)
        }
    }

    private func handleTap(_ id: String) {
        let now = Date()
        if lastTapID == id, let lastTapTime, now.timeIntervalSince(lastTapTime) < 0.45 {
            lastTapID = nil
            self.lastTapTime = nil
            ensureSelected(id)
            editingID = id
            return
        }
        lastTapID = id
        lastTapTime = now
        toggle(id)
    }

    private func ensureSelected(_ id: String) {
        var doc = baseDocument()
        if !doc.selections.contains(where: { $0.id == id }) {
            doc.selections.append(PracticeSelection(id: id, detail: ""))
        }
        clearOpposite(of: id, in: &doc)
        write(doc)
    }

    private func toggle(_ id: String) {
        var doc = baseDocument()
        if let index = doc.selections.firstIndex(where: { $0.id == id }) {
            doc.selections.remove(at: index)
        } else {
            doc.selections.append(PracticeSelection(id: id, detail: ""))
            clearOpposite(of: id, in: &doc)
        }
        write(doc)
    }

    private func clearOpposite(of id: String, in document: inout PracticeTemplateDocument) {
        let opposite = id.hasSuffix(".normal") ? String(id.dropLast(".normal".count)) : id + ".normal"
        document.selections.removeAll { $0.id == opposite }
    }

    private func setDetail(_ detail: String, for id: String) {
        var doc = baseDocument()
        guard let index = doc.selections.firstIndex(where: { $0.id == id }) else { return }
        doc.selections[index].detail = detail
        write(doc)
    }

    private func selectAllNormals() {
        for system in PracticeTemplateLibrary.systems(kind) {
            selectNormals(in: system)
        }
    }

    private func selectNormals(in system: String) {
        var doc = baseDocument()
        let rows = PracticeTemplateLibrary.findings(kind, system: system)
        let abnormalIDs = Set(rows.filter { !$0.isNormal }.map(\.id))
        doc.selections.removeAll { abnormalIDs.contains($0.id) }
        for finding in rows where finding.isNormal && !doc.selections.contains(where: { $0.id == finding.id }) {
            doc.selections.append(PracticeSelection(id: finding.id, detail: ""))
        }
        write(doc)
    }

    private func clearAll() {
        var doc = baseDocument()
        let ids = Set(PracticeTemplateLibrary.findings.filter { $0.kind == kind }.map(\.id))
        doc.selections.removeAll { ids.contains($0.id) }
        write(doc)
    }

    private func clear(_ system: String) {
        var doc = baseDocument()
        doc.selections.removeAll { selection in
            PracticeTemplateLibrary.finding(id: selection.id)?.system == system
        }
        write(doc)
    }
}

private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 640
        let rows = rows(width: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indexes: [Int], height: CGFloat)] {
        var rows: [(indexes: [Int], height: CGFloat)] = []
        var current: [Int] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.isEmpty, x + size.width > width {
                rows.append((current, rowHeight))
                current = []
                x = 0
                rowHeight = 0
            }
            current.append(index)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty {
            rows.append((current, rowHeight))
        }
        return rows
    }
}
