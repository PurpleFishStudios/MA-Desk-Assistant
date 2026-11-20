import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case tasks
    case timers
    case plants
    case icd10
    case cpt
    case localAI
    case dictation
    case settings
    case practiceCases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .tasks: return "Tasks"
        case .timers: return "Timers"
        case .plants: return "Plants"
        case .icd10: return "ICD-10 Reference"
        case .cpt: return "CPT Reference"
        case .dictation: return "Dictation Test"
        case .localAI: return "Local AI"
        case .settings: return "Settings"
        case .practiceCases: return "Practice Cases"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .tasks: return "checklist"
        case .timers: return "timer"
        case .plants: return "leaf.fill"
        case .icd10: return "cross.case.fill"
        case .cpt: return "list.bullet.rectangle"
        case .dictation: return "waveform"
        case .localAI: return "brain.head.profile"
        case .settings: return "gearshape.fill"
        case .practiceCases: return "note.text"
        }
    }
}
