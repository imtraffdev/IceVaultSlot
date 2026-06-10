import AVFoundation
import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class IceVaultStore: ObservableObject {
    @Published private(set) var vaults: [IceVaultVault] = []
    @Published private(set) var notes: [IceVaultNote] = []
    @Published private(set) var recentSearches: [IceVaultRecentSearch] = []
    @Published var settings = IceVaultSettings() {
        didSet { save() }
    }

    @AppStorage("iceVaultHasEntered") var hasEnteredVault = false

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documents.appendingPathComponent("ice-vault-data.json")
        load()
    }

    var pinnedNotes: [IceVaultNote] {
        notes.filter(\.isPinned).sorted(by: noteSort)
    }

    var starredNotes: [IceVaultNote] {
        notes.filter(\.isStarred).sorted(by: noteSort)
    }

    var secureNotes: [IceVaultNote] {
        notes.filter(\.isSecure).sorted(by: noteSort)
    }

    var upcomingReminders: [IceVaultNote] {
        notes
            .filter { note in
                guard let reminderDate = note.reminderDate else { return false }
                return reminderDate >= Calendar.current.startOfDay(for: Date())
            }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    var todayCaptureCount: Int {
        notes.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    func vault(for id: UUID) -> IceVaultVault? {
        vaults.first { $0.id == id }
    }

    func noteCount(for vault: IceVaultVault) -> Int {
        notes.filter { $0.vaultId == vault.id }.count
    }

    func notes(in vault: IceVaultVault) -> [IceVaultNote] {
        notes.filter { $0.vaultId == vault.id }.sorted(by: noteSort)
    }

    func upsertNote(_ note: IceVaultNote) {
        var updated = note
        updated.updatedAt = Date()

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = updated
        } else {
            notes.append(updated)
        }
        save()
    }

    func deleteNote(_ note: IceVaultNote) {
        notes.removeAll { $0.id == note.id }
        if let url = note.voiceRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        save()
    }

    func toggleChecklistItem(noteId: UUID, itemId: UUID) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = notes[noteIndex].checklistItems.firstIndex(where: { $0.id == itemId })
        else { return }

        notes[noteIndex].checklistItems[itemIndex].isCompleted.toggle()
        notes[noteIndex].updatedAt = Date()
        save()
    }

    func createVault(name: String, iconName: String, colorName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vaults.append(IceVaultVault(name: trimmed, iconName: iconName, colorName: colorName))
        save()
    }

    func updateVault(_ vault: IceVaultVault) {
        guard let index = vaults.firstIndex(where: { $0.id == vault.id }) else { return }
        vaults[index] = vault
        save()
    }

    func deleteVault(_ vault: IceVaultVault) {
        guard vaults.count > 1 else { return }
        let fallback = vaults.first { $0.id != vault.id }?.id
        notes = notes.map { note in
            guard note.vaultId == vault.id, let fallback else { return note }
            var updated = note
            updated.vaultId = fallback
            updated.updatedAt = Date()
            return updated
        }
        vaults.removeAll { $0.id == vault.id }
        if settings.defaultVaultId == vault.id {
            settings.defaultVaultId = fallback
        }
        save()
    }

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.query.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(IceVaultRecentSearch(query: trimmed), at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        save()
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        save()
    }

    func resetLocalData() {
        for note in notes {
            if let url = note.voiceRecordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        seedDefaults()
        recentSearches = []
        settings = IceVaultSettings(defaultVaultId: vaults.first?.id)
        save()
    }

    func search(_ query: String, filter: IceVaultSearchFilter) -> [IceVaultNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredByType = notes.filter { note in
            switch filter {
            case .all:
                return true
            case .notes:
                return [.text, .mixed].contains(note.type)
            case .checklists:
                return note.type == .checklist
            case .images:
                return note.type == .photo || note.imageData != nil
            case .voice:
                return note.type == .voice || note.voiceRecordingURL != nil
            case .pinned:
                return note.isPinned
            case .reminders:
                return note.reminderDate != nil
            }
        }

        guard !trimmed.isEmpty else { return filteredByType.sorted(by: noteSort) }
        return filteredByType.filter { note in
            let vaultName = vault(for: note.vaultId)?.name ?? ""
            let checklistText = note.checklistItems.map(\.text).joined(separator: " ")
            let haystack = ([note.title, note.body, vaultName, checklistText] + note.tags).joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
        .sorted(by: noteSort)
    }

    func exportURL() -> URL? {
        save()
        return fileURL
    }

    func defaultVaultId() -> UUID {
        settings.defaultVaultId ?? vaults.first?.id ?? UUID()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder.iceVault.decode(IceVaultSnapshot.self, from: data)
        else {
            seedDefaults()
            settings.defaultVaultId = vaults.first?.id
            save()
            return
        }

        vaults = snapshot.vaults
        notes = snapshot.notes
        recentSearches = snapshot.recentSearches
        settings = snapshot.settings

        if vaults.isEmpty {
            seedDefaults()
            save()
        }
    }

    private func save() {
        let snapshot = IceVaultSnapshot(
            vaults: vaults,
            notes: notes,
            recentSearches: recentSearches,
            settings: settings
        )
        guard let data = try? JSONEncoder.iceVault.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func seedDefaults() {
        let seedVaults = [
            IceVaultVault(name: "Brand Ideas", iconName: "briefcase.fill", colorName: "blue"),
            IceVaultVault(name: "Journal", iconName: "book.closed.fill", colorName: "purple"),
            IceVaultVault(name: "Travel", iconName: "suitcase.fill", colorName: "cyan"),
            IceVaultVault(name: "Fitness", iconName: "heart.fill", colorName: "green"),
            IceVaultVault(name: "Recipes", iconName: "fork.knife", colorName: "orange"),
            IceVaultVault(name: "Content", iconName: "play.rectangle.fill", colorName: "pink"),
            IceVaultVault(name: "Personal", iconName: "person.fill", colorName: "mint"),
            IceVaultVault(name: "Work", iconName: "laptopcomputer", colorName: "indigo")
        ]
        vaults = seedVaults

        let brand = seedVaults[0].id
        let travel = seedVaults[2].id
        let work = seedVaults[7].id
        notes = [
            IceVaultNote(
                title: "Product launch brainstorm",
                body: "New feature set, target audience, launch plan, and retention hooks.",
                type: .mixed,
                vaultId: brand,
                tags: ["roadmap", "launch", "planning"],
                isPinned: true,
                isStarred: true,
                isSecure: false,
                reminderDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                checklistItems: [
                    IceVaultChecklistItem(text: "Build beautiful fast experience", isCompleted: true, order: 0),
                    IceVaultChecklistItem(text: "Offline-first and secure", isCompleted: true, order: 1),
                    IceVaultChecklistItem(text: "Integrate reminders", isCompleted: false, order: 2)
                ]
            ),
            IceVaultNote(
                title: "Iceland trip ideas",
                body: "Places to visit, budget, packing list, and aurora photo spots.",
                type: .checklist,
                vaultId: travel,
                tags: ["iceland", "travel"],
                isPinned: false,
                isStarred: true,
                isSecure: false,
                reminderDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
                checklistItems: [
                    IceVaultChecklistItem(text: "Book glacier tour", isCompleted: false, order: 0),
                    IceVaultChecklistItem(text: "Pack thermal layers", isCompleted: true, order: 1),
                    IceVaultChecklistItem(text: "Save offline map", isCompleted: false, order: 2)
                ]
            ),
            IceVaultNote(
                title: "Q2 review prep",
                body: "Gather metrics, prepare deck, and review goals.",
                type: .text,
                vaultId: work,
                tags: ["work", "review"],
                isPinned: true,
                isStarred: false,
                isSecure: true,
                reminderDate: Calendar.current.date(byAdding: .hour, value: 8, to: Date()),
                checklistItems: []
            )
        ]
    }

    private func noteSort(_ lhs: IceVaultNote, _ rhs: IceVaultNote) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
    }
}

enum IceVaultSearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case notes = "Notes"
    case checklists = "Checklists"
    case images = "Images"
    case voice = "Voice"
    case pinned = "Pinned"
    case reminders = "Reminders"

    var id: String { rawValue }
}

private struct IceVaultSnapshot: Codable {
    var vaults: [IceVaultVault]
    var notes: [IceVaultNote]
    var recentSearches: [IceVaultRecentSearch]
    var settings: IceVaultSettings
}

extension JSONEncoder {
    static var iceVault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iceVault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
final class IceVaultAuthenticator: ObservableObject {
    @Published var lastError: String?

    func unlock(reason: String = "Unlock secure Ice Vault notes") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription ?? "Device authentication is not available."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return success
        } catch {
            lastError = "Authentication was cancelled or failed."
            return false
        }
    }
}

@MainActor
final class IceVaultAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var lastRecordingURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else {
                    self.errorMessage = "Microphone access is needed for voice notes."
                    return
                }
                self.beginRecording()
            }
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = documents.appendingPathComponent("ice-vault-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            lastRecordingURL = url
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = "Voice recording could not start."
            isRecording = false
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
            if !flag {
                errorMessage = "Voice recording was not saved."
            }
        }
    }
}
