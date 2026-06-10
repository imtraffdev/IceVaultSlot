import Foundation
import SwiftUI

enum IceVaultNoteType: String, Codable, CaseIterable, Identifiable {
    case text
    case checklist
    case voice
    case photo
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Note"
        case .checklist: "Checklist"
        case .voice: "Voice"
        case .photo: "Photo"
        case .mixed: "Mixed"
        }
    }

    var symbol: String {
        switch self {
        case .text: "doc.text.fill"
        case .checklist: "checklist.checked"
        case .voice: "mic.fill"
        case .photo: "photo.fill"
        case .mixed: "square.grid.2x2.fill"
        }
    }
}

struct IceVaultChecklistItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var isCompleted: Bool
    var order: Int
}

struct IceVaultVault: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var iconName: String
    var colorName: String
    var createdAt = Date()
}

struct IceVaultNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var createdAt = Date()
    var updatedAt = Date()
    var type: IceVaultNoteType
    var vaultId: UUID
    var tags: [String]
    var isPinned: Bool
    var isStarred: Bool
    var isSecure: Bool
    var reminderDate: Date? = nil
    var imageData: Data? = nil
    var imageURL: URL? = nil
    var voiceRecordingURL: URL? = nil
    var checklistItems: [IceVaultChecklistItem] = []
}

struct IceVaultRecentSearch: Identifiable, Codable, Equatable {
    var id = UUID()
    var query: String
    var createdAt = Date()
}

struct IceVaultSettings: Codable, Equatable {
    var enableFaceID = true
    var appTheme = "Ice Light"
    var defaultVaultId: UUID?
}

enum IceVaultPalette {
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "cyan": return .cyan
        case "purple": return .purple
        case "mint": return .mint
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "indigo": return .indigo
        default: return .blue
        }
    }

    static let colorNames = ["blue", "cyan", "purple", "mint", "green", "orange", "pink", "indigo"]
}
