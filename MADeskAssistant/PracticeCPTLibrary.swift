//
//  PracticeCPTLibrary.swift
//  MADeskAssistant
//
//  A short teaching list. This is not the AMA CPT code set and not a
//  final billing code.
//

import Foundation
import SwiftUI

struct PracticeCPTCode: Identifiable, Hashable {
    let code: String
    let label: String
    let group: String
    var id: String { code }
}

struct PracticeCPTEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var code: String
    var descriptionText: String
    var linkedICDCodes: [String]

    init(id: UUID = UUID(), code: String, descriptionText: String, linkedICDCodes: [String] = []) {
        self.id = id
        self.code = code
        self.descriptionText = descriptionText
        self.linkedICDCodes = linkedICDCodes
    }
}

enum PracticeCPTLibrary {
    static let codes: [PracticeCPTCode] = [
        PracticeCPTCode(code: "99202", label: "Office visit, new patient, straightforward", group: "Office visit"),
        PracticeCPTCode(code: "99203", label: "Office visit, new patient, low complexity", group: "Office visit"),
        PracticeCPTCode(code: "99204", label: "Office visit, new patient, moderate complexity", group: "Office visit"),
        PracticeCPTCode(code: "99205", label: "Office visit, new patient, high complexity", group: "Office visit"),
        PracticeCPTCode(code: "99211", label: "Office visit, established patient, minimal", group: "Office visit"),
        PracticeCPTCode(code: "99212", label: "Office visit, established patient, straightforward", group: "Office visit"),
        PracticeCPTCode(code: "99213", label: "Office visit, established patient, low complexity", group: "Office visit"),
        PracticeCPTCode(code: "99214", label: "Office visit, established patient, moderate complexity", group: "Office visit"),
        PracticeCPTCode(code: "99215", label: "Office visit, established patient, high complexity", group: "Office visit"),
        PracticeCPTCode(code: "99385", label: "Preventive visit, new patient, age 18–39", group: "Preventive visit"),
        PracticeCPTCode(code: "99386", label: "Preventive visit, new patient, age 40–64", group: "Preventive visit"),
        PracticeCPTCode(code: "99395", label: "Preventive visit, established patient, age 18–39", group: "Preventive visit"),
        PracticeCPTCode(code: "99396", label: "Preventive visit, established patient, age 40–64", group: "Preventive visit"),
        PracticeCPTCode(code: "36415", label: "Collection of venous blood by venipuncture", group: "Common procedures"),
        PracticeCPTCode(code: "81002", label: "Urinalysis, non-automated, without microscopy", group: "Common procedures"),
        PracticeCPTCode(code: "87880", label: "Strep A antigen test", group: "Common procedures"),
        PracticeCPTCode(code: "90471", label: "Immunization administration, first injection", group: "Common procedures"),
        PracticeCPTCode(code: "96372", label: "Therapeutic injection, subcutaneous or intramuscular", group: "Common procedures"),
        PracticeCPTCode(code: "93000", label: "Electrocardiogram with interpretation and report", group: "Common procedures"),
        PracticeCPTCode(code: "69210", label: "Removal of impacted cerumen, one ear", group: "Common procedures")
    ]

    static func code(_ value: String) -> PracticeCPTCode? {
        codes.first { $0.code == value }
    }

    static func matches(_ query: String) -> [PracticeCPTCode] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return codes }
        return codes.filter {
            $0.code.contains(text) || $0.label.lowercased().contains(text) || $0.group.lowercased().contains(text)
        }
    }

    static func lookupReply(for term: String) -> String {
        let text = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = matches(text)
        if found.isEmpty {
            return """
            No practice CPT code matched “\(text)”.
            Open CPT Reference in the sidebar, or try a code such as 99213.
            This list is a teaching subset, not the official CPT code set, and it does not decide whether a code is appropriate to bill.
            """
        }
        let rows = found.prefix(8).map { "• \($0.code) — \($0.label) (\($0.group))" }.joined(separator: "\n")
        return """
        Practice CPT matches for “\(text)”:
        \(rows)

        These are not a final billing choice. To attach one to the current fictional note, say “Add CPT \(found[0].code)”. Then link an ICD-10-CM reference in Practice Cases.
        """
    }
}

enum PracticeCPTStore {
    static func load(_ raw: String) -> [PracticeCPTEntry] {
        guard let data = raw.data(using: .utf8), !raw.isEmpty else { return [] }
        return (try? JSONDecoder().decode([PracticeCPTEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [PracticeCPTEntry]) -> String {
        guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func displayLine(_ entry: PracticeCPTEntry) -> String {
        let links = entry.linkedICDCodes.filter { !$0.isEmpty }
        if links.isEmpty {
            return "\(entry.code) — \(entry.descriptionText)"
        }
        return "\(entry.code) — \(entry.descriptionText); linked ICD-10-CM: \(links.joined(separator: ", "))"
    }
}

struct PracticeCPTPicker: View {
    @Environment(\.dismiss) private var dismiss
    let existingCodes: Set<String>
    let onAdd: (PracticeCPTCode) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Practice CPT subset. These short labels are for fictional cases. They are not the official CPT code set and not a final billing choice.")
                    .font(.callout)
                    .foregroundStyle(.orange)

                TextField("Search a code or visit type, such as 99213 or strep", text: $query)
                    .textFieldStyle(.roundedBorder)

                List(PracticeCPTLibrary.matches(query)) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.code) — \(item.label)")
                            Text(item.group)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if existingCodes.contains(item.code) {
                            Text("Added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Add") { onAdd(item) }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("CPT practice library")
            .toolbar {
                Button("Close") { dismiss() }
            }
        }
    }
}

struct FlowCPTLinks: View {
    let codes: [String]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(codes, id: \.self) { code in
                Button(code) { onToggle(code) }
                    .buttonStyle(.bordered)
                    .tint(selected.contains(code) ? .accentColor : .gray)
            }
        }
    }
}
