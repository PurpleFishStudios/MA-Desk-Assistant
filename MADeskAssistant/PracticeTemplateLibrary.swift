//
//  PracticeTemplateLibrary.swift
//  MADeskAssistant
//
//  Original teaching findings for fictional practice notes.
//  This is not an EHR macro and not an observed exam.
//

import Foundation

enum PracticeTemplateKind: String, Codable {
    case ros
    case pe
}

struct PracticeFinding: Identifiable, Hashable {
    let id: String
    let kind: PracticeTemplateKind
    let system: String
    let label: String
    let triggers: [String]
    let isNormal: Bool
}

struct PracticeSelection: Codable, Equatable, Identifiable {
    var id: String
    var detail: String
}

struct PracticeTemplateDocument: Codable, Equatable {
    var selections: [PracticeSelection]
    var extraNote: String

    static let empty = PracticeTemplateDocument(selections: [], extraNote: "")
}

enum PracticeTemplateLibrary {
    static let findings: [PracticeFinding] = expandedROS + peFindings

    static func systems(_ kind: PracticeTemplateKind) -> [String] {
        var seen: [String] = []
        for finding in findings where finding.kind == kind && !seen.contains(finding.system) {
            seen.append(finding.system)
        }
        return seen
    }

    static func findings(_ kind: PracticeTemplateKind, system: String) -> [PracticeFinding] {
        findings.filter { $0.kind == kind && $0.system == system }
    }

    static func finding(id: String) -> PracticeFinding? {
        findings.first { $0.id == id }
    }

    private static var expandedROS: [PracticeFinding] {
        var result: [PracticeFinding] = []
        for system in rosSymptoms.map(\.system) where !result.contains(where: { $0.system == system && $0.isNormal }) {
            let group = rosSymptoms.filter { $0.system == system }
            result.append(contentsOf: group.map { symptom in
                PracticeFinding(
                    id: symptom.id + ".normal",
                    kind: .ros,
                    system: symptom.system,
                    label: "No \(symptom.label.lowercased())",
                    triggers: [],
                    isNormal: true
                )
            })
            result.append(contentsOf: group)
        }
        return result
    }

    private static let rosSymptoms: [PracticeFinding] = [
        item("ros.constitutional.fever", .ros, "Constitutional", "Fever", ["fever"], false),
        item("ros.constitutional.chills", .ros, "Constitutional", "Chills", ["chills"], false),
        item("ros.constitutional.night_sweats", .ros, "Constitutional", "Night sweats", ["night sweats"], false),
        item("ros.constitutional.weight_change", .ros, "Constitutional", "Weight change", ["weight loss", "weight gain", "weight change"], false),
        item("ros.constitutional.fatigue", .ros, "Constitutional", "Fatigue", ["fatigue"], false),
        item("ros.eyes.vision", .ros, "Eyes", "Vision change", ["vision change", "blurred vision"], false),
        item("ros.eyes.pain", .ros, "Eyes", "Eye pain", ["eye pain"], false),
        item("ros.eyes.redness", .ros, "Eyes", "Eye redness", ["red eye"], false),
        item("ros.enmt.ear_pain", .ros, "ENMT", "Ear pain", ["ear pain", "earache"], false),
        item("ros.enmt.hearing", .ros, "ENMT", "Hearing change", ["hearing loss", "hearing change"], false),
        item("ros.enmt.congestion", .ros, "ENMT", "Nasal congestion", ["congestion", "runny nose"], false),
        item("ros.enmt.sore_throat", .ros, "ENMT", "Sore throat", ["sore throat"], false),
        item("ros.cv.chest_pain", .ros, "Cardiovascular", "Chest pain", ["chest pain"], false),
        item("ros.cv.palpitations", .ros, "Cardiovascular", "Palpitations", ["palpitations"], false),
        item("ros.cv.leg_swelling", .ros, "Cardiovascular", "Leg swelling", ["leg swelling", "edema"], false),
        item("ros.resp.cough", .ros, "Respiratory", "Cough", ["cough"], false),
        item("ros.resp.wheeze", .ros, "Respiratory", "Wheezing", ["wheezing", "wheeze"], false),
        item("ros.resp.sob", .ros, "Respiratory", "Shortness of breath", ["shortness of breath", "dyspnea", "sob"], false),
        item("ros.gi.abdominal_pain", .ros, "Gastrointestinal", "Abdominal pain", ["abdominal pain", "stomach pain"], false),
        item("ros.gi.nausea", .ros, "Gastrointestinal", "Nausea", ["nausea"], false),
        item("ros.gi.vomiting", .ros, "Gastrointestinal", "Vomiting", ["vomiting"], false),
        item("ros.gi.diarrhea", .ros, "Gastrointestinal", "Diarrhea", ["diarrhea"], false),
        item("ros.gu.dysuria", .ros, "Genitourinary", "Dysuria", ["dysuria", "painful urination"], false),
        item("ros.gu.frequency", .ros, "Genitourinary", "Urinary frequency", ["urinary frequency"], false),
        item("ros.gu.hematuria", .ros, "Genitourinary", "Hematuria", ["hematuria"], false),
        item("ros.msk.muscle_aches", .ros, "Musculoskeletal", "Muscle aches", ["muscle aches", "myalgia", "body aches"], false),
        item("ros.msk.joint_pain", .ros, "Musculoskeletal", "Joint pain", ["joint pain", "arthralgia"], false),
        item("ros.msk.back_pain", .ros, "Musculoskeletal", "Back pain", ["back pain"], false),
        item("ros.msk.joint_swelling", .ros, "Musculoskeletal", "Joint swelling", ["joint swelling"], false),
        item("ros.skin.rash", .ros, "Skin", "Rash", ["rash"], false),
        item("ros.skin.itching", .ros, "Skin", "Itching", ["itching"], false),
        item("ros.neuro.headache", .ros, "Neurologic", "Headache", ["headache", "headaches"], false),
        item("ros.neuro.dizziness", .ros, "Neurologic", "Dizziness", ["dizziness", "vertigo"], false),
        item("ros.neuro.numbness", .ros, "Neurologic", "Numbness", ["numbness"], false),
        item("ros.psych.depression", .ros, "Psychiatric", "Depression", ["depression"], false),
        item("ros.psych.anxiety", .ros, "Psychiatric", "Anxiety", ["anxiety"], false),
        item("ros.psych.sleep", .ros, "Psychiatric", "Sleep disturbance", ["insomnia"], false),
        item("ros.heme.bruising", .ros, "Hematologic/Lymphatic", "Easy bruising", ["bruising"], false),
        item("ros.heme.glands", .ros, "Hematologic/Lymphatic", "Swollen glands", ["swollen glands"], false),
        item("ros.allergy.sneezing", .ros, "Allergic/Immunologic", "Sneezing", ["sneezing"], false),
        item("ros.allergy.hives", .ros, "Allergic/Immunologic", "Hives", ["hives"], false)
    ]

    private static let peFindings: [PracticeFinding] = [
        item("pe.general.nad", .pe, "General", "No acute distress", ["no acute distress"], true),
        item("pe.general.uncomfortable", .pe, "General", "Appears uncomfortable", ["uncomfortable"], false),
        item("pe.general.ambulating", .pe, "General", "Ambulating normally", ["ambulating"], true),
        item("pe.psych.alert", .pe, "Psychiatric", "Alert", ["alert"], true),
        item("pe.psych.mood", .pe, "Psychiatric", "Normal mood and affect", ["normal mood"], true),
        item("pe.psych.oriented", .pe, "Psychiatric", "Oriented to person, place, and time", ["oriented"], true),
        item("pe.head.normocephalic", .pe, "Head", "Normocephalic", ["normocephalic"], true),
        item("pe.head.atraumatic", .pe, "Head", "Atraumatic", ["atraumatic"], true),
        item("pe.head.tenderness", .pe, "Head", "Scalp tenderness", ["scalp tenderness"], false),
        item("pe.eyes.perrla", .pe, "Eyes", "Pupils equal and reactive", ["perrla", "pupils equal"], true),
        item("pe.eyes.eom", .pe, "Eyes", "Extraocular movements intact", ["extraocular"], true),
        item("pe.eyes.injection", .pe, "Eyes", "Conjunctival injection", ["conjunctival injection", "red eye"], false),
        item("pe.enmt.tm_clear", .pe, "ENMT", "Tympanic membranes clear", ["tympanic membranes clear", "tms clear"], true),
        item("pe.enmt.congestion", .pe, "ENMT", "Nasal congestion", ["nasal congestion"], false),
        item("pe.enmt.erythema", .pe, "ENMT", "Pharyngeal erythema", ["pharyngeal erythema", "erythema"], false),
        item("pe.neck.supple", .pe, "Neck", "Supple", ["neck supple"], true),
        item("pe.neck.nodes", .pe, "Neck", "Cervical lymphadenopathy", ["cervical lymphadenopathy", "lymphadenopathy"], false),
        item("pe.lungs.clear", .pe, "Lungs", "Clear to auscultation", ["clear to auscultation", "lungs clear"], true),
        item("pe.lungs.wheeze", .pe, "Lungs", "Wheezing", ["wheezing", "wheeze"], false),
        item("pe.lungs.rales", .pe, "Lungs", "Rales", ["rales", "crackles"], false),
        item("pe.lungs.rhonchi", .pe, "Lungs", "Rhonchi", ["rhonchi"], false),
        item("pe.cv.rrr", .pe, "Cardiovascular", "Regular rate and rhythm", ["regular rate", "rrr"], true),
        item("pe.cv.murmur", .pe, "Cardiovascular", "Murmur", ["murmur"], false),
        item("pe.cv.tachycardia", .pe, "Cardiovascular", "Tachycardia", ["tachycardia"], false),
        item("pe.abd.soft", .pe, "Abdomen", "Soft", ["abdomen soft"], true),
        item("pe.abd.tender", .pe, "Abdomen", "Tender", ["abdominal tenderness", "tender"], false),
        item("pe.abd.guarding", .pe, "Abdomen", "Guarding", ["guarding"], false),
        item("pe.msk.full_rom", .pe, "Musculoskeletal", "Full range of motion", ["full range of motion"], true),
        item("pe.msk.tenderness", .pe, "Musculoskeletal", "Muscle tenderness", ["muscle tenderness"], false),
        item("pe.msk.swelling", .pe, "Musculoskeletal", "Joint swelling", ["joint swelling"], false),
        item("pe.skin.warm", .pe, "Skin", "Warm and dry", ["warm and dry"], true),
        item("pe.skin.rash", .pe, "Skin", "Rash", ["rash"], false),
        item("pe.neuro.intact", .pe, "Neurologic", "No focal deficit", ["no focal deficit", "neurologically intact"], true),
        item("pe.neuro.weakness", .pe, "Neurologic", "Weakness", ["weakness"], false)
    ]

    private static func item(
        _ id: String,
        _ kind: PracticeTemplateKind,
        _ system: String,
        _ label: String,
        _ triggers: [String],
        _ isNormal: Bool
    ) -> PracticeFinding {
        PracticeFinding(id: id, kind: kind, system: system, label: label, triggers: triggers, isNormal: isNormal)
    }
}

enum PracticeTemplateStore {
    private static let prefix = "[[practice-template-v1]]\n"

    static func exportText(from stored: String) -> String {
        guard let document = decode(stored) else {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let selected = document.selections.compactMap { selection -> String? in
            guard let finding = PracticeTemplateLibrary.finding(id: selection.id) else { return nil }
            let detail = selection.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? finding.label : "\(finding.label) (\(detail))"
        }
        let extra = document.extraNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return (selected + (extra.isEmpty ? [] : [extra])).joined(separator: "; ")
    }

    static func isBlank(_ stored: String) -> Bool {
        exportText(from: stored).isEmpty
    }

    static func decode(_ stored: String) -> PracticeTemplateDocument? {
        guard stored.hasPrefix(prefix) else { return nil }
        let payload = String(stored.dropFirst(prefix.count))
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PracticeTemplateDocument.self, from: data)
    }

    static func encode(_ document: PracticeTemplateDocument) -> String {
        let order = Dictionary(uniqueKeysWithValues: PracticeTemplateLibrary.findings.enumerated().map { ($1.id, $0) })
        var copy = document
        copy.selections.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        let data = (try? JSONEncoder().encode(copy)) ?? Data("{}".utf8)
        return prefix + (String(data: data, encoding: .utf8) ?? "{}")
    }

    static func encoded(_ kind: PracticeTemplateKind, matching text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let selections = PracticeTemplateLibrary.findings.compactMap { finding -> PracticeSelection? in
            guard finding.kind == kind, !finding.triggers.isEmpty else { return nil }
            guard PracticeNoteTemplate.isAffirmed(finding.triggers, in: trimmed) else { return nil }
            return PracticeSelection(id: finding.id, detail: "")
        }
        guard !selections.isEmpty else { return "" }
        return encode(PracticeTemplateDocument(selections: selections, extraNote: ""))
    }

    static func remove(phrase: String, from stored: String) -> (text: String, removed: Bool)? {
        guard var document = decode(stored) else { return nil }
        let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 3 else { return (stored, false) }
        let before = document.selections.count
        document.selections.removeAll { selection in
            guard let finding = PracticeTemplateLibrary.finding(id: selection.id) else { return false }
            return finding.label.lowercased().contains(needle)
                || finding.system.lowercased() == needle
                || selection.detail.lowercased().contains(needle)
        }
        let noteBefore = document.extraNote
        if document.extraNote.lowercased().contains(needle) {
            document.extraNote = ""
        }
        let removed = document.selections.count != before || document.extraNote != noteBefore
        return (encode(document), removed)
    }

    static func select(id: String, detail: String, in stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        var document = decode(stored) ?? PracticeTemplateDocument(
            selections: [],
            extraNote: decode(stored) == nil ? trimmed : ""
        )
        let opposite = id.hasSuffix(".normal") ? String(id.dropLast(".normal".count)) : id + ".normal"
        document.selections.removeAll { $0.id == id || $0.id == opposite }
        document.selections.append(PracticeSelection(id: id, detail: detail))
        return encode(document)
    }

    static func add(phrase: String, to stored: String, kind: PracticeTemplateKind) -> String {
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        var document = decode(stored) ?? PracticeTemplateDocument(
            selections: [],
            extraNote: stored.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let finding = PracticeTemplateLibrary.findings.first(where: {
            $0.kind == kind && $0.label.localizedCaseInsensitiveCompare(clean) == .orderedSame
        }) {
            if !document.selections.contains(where: { $0.id == finding.id }) {
                document.selections.append(PracticeSelection(id: finding.id, detail: ""))
            }
        } else if !document.extraNote.localizedCaseInsensitiveContains(clean) {
            document.extraNote = [document.extraNote, clean]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
        }
        return encode(document)
    }
}
