//
//  CPTReferenceView.swift
//  MADeskAssistant
//
//  Teaching CPT subset. Not the AMA CPT code set and not a billing check.
//

import SwiftUI

struct CPTReferenceView: View {
    @State private var query = ""
    @State private var selectedCode: String?

    private var results: [PracticeCPTCode] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? PracticeCPTLibrary.codes : PracticeCPTLibrary.matches(text)
    }

    private var selected: PracticeCPTCode? {
        guard let selectedCode else { return nil }
        return PracticeCPTLibrary.code(selectedCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CPT Reference")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Practice subset for fictional cases")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("These short labels are for practice only. They are not the official CPT code set, and choosing one does not mean it is the correct billing code. Confirm the code, the linked ICD-10-CM reference, and the assignment before you submit.")
                .font(.callout)
                .foregroundStyle(.orange)

            TextField("Search a code or term, such as 99213 or strep", text: $query)
                .textFieldStyle(.roundedBorder)

            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                resultsPanel
                    .frame(minWidth: 290, idealWidth: 370, maxWidth: 440)
                Divider()
                detailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(24)
        .navigationTitle("CPT Reference")
    }

    private var statusLine: String {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "Showing all \(PracticeCPTLibrary.codes.count) practice codes. Type a code or term to narrow the list."
        }
        if results.isEmpty {
            return "No practice CPT code matched “\(text)”."
        }
        return "\(results.count) practice match\(results.count == 1 ? "" : "es")."
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.headline)
            if results.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try 99213, office visit, or strep.")
                )
            } else {
                List(results, selection: $selectedCode) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.code)
                            .font(.headline)
                        Text(item.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(item.group)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
                    }
                    .tag(item.code)
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }

    private var detailPanel: some View {
        Group {
            if let selected {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selected.code)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
                    Text(selected.label)
                        .font(.title3)
                    Text(selected.group)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("To put this on a fictional note, open Practice Cases and use Look Up CPT, or tell Home: “Add CPT \(selected.code)”. Then link the ICD-10-CM references that support it.")
                        .font(.callout)
                    Text("This screen does not check payer rules, age, time, or whether the code is appropriate to bill.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "Choose a code",
                    systemImage: "book.closed",
                    description: Text("Select a search result to review its practice label.")
                )
            }
        }
    }
}
