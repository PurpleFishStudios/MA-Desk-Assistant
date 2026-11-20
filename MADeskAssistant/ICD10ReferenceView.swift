import SwiftUI
import ICD10CM

struct ICD10ReferenceView: View {
    @State private var store: ICD10Store?
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var selectedCode: String?
    @State private var detail: CodeDetail?
    @State private var status: String?
    @State private var isSearching = false

    private let searchOptions = SearchOptions(useSynonyms: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ICD-10-CM Reference")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("FY2027 • Effective October 1, 2026 – September 30, 2027")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("For fictional practice cases only. Search results are reference candidates, not diagnoses or final billing codes. Verify the Index, Tabular List, documentation, and applicable guidelines.")
                .font(.callout)
                .foregroundStyle(.orange)

            TextField("Search a code or term, e.g. E11.9 or hypertension", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search ICD-10-CM FY2027")

            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                resultsPanel
                    .frame(minWidth: 290, idealWidth: 370, maxWidth: 440)
                Divider()
                detailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(24)
        .navigationTitle("ICD-10-CM Reference")
        .task {
            guard store == nil else { return }
            do {
                store = try ICD10Store()
            } catch {
                status = "Could not open the bundled ICD-10-CM database: \(error.localizedDescription)"
            }
        }
        .task(id: query) {
            guard let store else { return }
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                store.cancelInFlightSearches()
                hits = []
                selectedCode = nil
                detail = nil
                isSearching = false
                status = "Type a fictional-case code or term to begin."
                return
            }

            // Reset results so a previous query cannot be mistaken for the current query.
            hits = []
            selectedCode = nil
            detail = nil
            isSearching = true
            status = nil

            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                try Task.checkCancellation()
                let found = try await store.searchAsync(text, limit: 25, options: searchOptions)
                try Task.checkCancellation()
                hits = found
                status = found.isEmpty ? "No matches. Try a different term or code." : nil
                isSearching = false
            } catch is CancellationError {
                // A newer query replaces this one.
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                status = "Search failed: \(error.localizedDescription)"
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
                if found == nil { status = "No detail found for \(selectedCode)." }
            } catch is CancellationError {
                // Selection changed before detail was shown.
            } catch {
                guard !Task.isCancelled else { return }
                status = "Could not load \(selectedCode): \(error.localizedDescription)"
            }
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Results").font(.headline)
                Spacer()
                if isSearching { ProgressView().controlSize(.small) }
            }
            List {
                ForEach(hits, id: \.code.code) { hit in
                    Button {
                        selectedCode = hit.code.code
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hit.code.code).font(.headline)
                            Text(hit.code.longDescription)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            if hit.code.requiresMoreCharacters || hit.isIncomplete {
                                Label("More specificity required", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Billable code • verify before use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedCode == hit.code.code ? Color.accentColor.opacity(0.15) : Color.clear)
                }
            }
            .listStyle(.inset)
        }
    }

    private var detailPanel: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 14) {
                    Text(detail.code.code)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(detail.code.longDescription)
                        .font(.title3)
                        .textSelection(.enabled)

                    if detail.requiresMoreCharacters {
                        Label("Header code: more characters required; do not treat as a final code.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Billable code; still requires documentation and coding review.")
                            .foregroundStyle(.secondary)
                    }

                    if let chapter = detail.code.chapter {
                        Text("Chapter \(chapter.number): \(chapter.title)")
                            .font(.caption)
                    }
                    if let section = detail.code.section {
                        Text("Section \(section.label): \(section.title)")
                            .font(.caption)
                    }

                    Divider()
                    Text("Instructional notes").font(.headline)
                    if detail.notes.isEmpty {
                        Text("No instructional notes returned for this code.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(detail.notes.enumerated()), id: \.offset) { _, note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(noteLabel(note.kind))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(note.kind == .excludes1 ? .orange : .primary)
                                Text(note.text)
                                    .textSelection(.enabled)
                                Text("Source: \(sourceLabel(note.source))\(note.isInherited ? " (inherited)" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !detail.seventhCharacters.isEmpty {
                        Divider()
                        Text("7th-character definitions").font(.headline)
                        ForEach(detail.seventhCharacters, id: \.character) { option in
                            Text("\(option.character): \(option.meaning)")
                        }
                    }

                    if !detail.children.isEmpty {
                        Divider()
                        Text("More specific child codes").font(.headline)
                        ForEach(detail.children, id: \.code) { child in
                            Button("\(child.code) — \(child.longDescription)") {
                                selectedCode = child.code
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("Choose a code", systemImage: "text.book.closed",
                                       description: Text("Select a search result to review its details and notes."))
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private func noteLabel(_ kind: NoteKind) -> String {
        switch kind {
        case .excludes1: return "Excludes1 — review carefully"
        case .excludes2: return "Excludes2"
        case .includes: return "Includes"
        case .inclusionTerm: return "Inclusion term"
        case .codeFirst: return "Code first"
        case .useAdditionalCode: return "Use additional code"
        case .codeAlso: return "Code also"
        case .note: return "Note"
        }
    }

    private func sourceLabel(_ source: NoteSource) -> String {
        switch source {
        case .code(let code): return "code \(code)"
        case .section(let section): return "section \(section)"
        case .chapter(let chapter): return "chapter \(chapter)"
        }
    }
}
