import PhotosUI
import SwiftUI

enum IceVaultTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case vaults = "Vaults"
    case create = "Create"
    case search = "Search"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .vaults: "archivebox.fill"
        case .create: "plus.circle.fill"
        case .search: "magnifyingglass"
        case .settings: "gearshape.fill"
        }
    }
}

struct IceVaultExperience: View {
    @EnvironmentObject private var store: IceVaultStore
    @StateObject private var authenticator = IceVaultAuthenticator()
    @State private var selectedTab: IceVaultTab = IceVaultTab(
        rawValue: UserDefaults.standard.string(forKey: "iceVaultSelectedTab") ?? ""
    ) ?? .home
    @State private var editorNote: IceVaultNote?
    @State private var alertMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            IceVaultHomeView(openEditor: openEditor, quickCreate: quickCreate)
                .tabItem { Label(IceVaultTab.home.rawValue, systemImage: IceVaultTab.home.symbol) }
                .tag(IceVaultTab.home)

            IceVaultVaultsView(openEditor: openEditor)
                .tabItem { Label(IceVaultTab.vaults.rawValue, systemImage: IceVaultTab.vaults.symbol) }
                .tag(IceVaultTab.vaults)

            IceVaultActionView(openEditor: openEditor, quickCreate: quickCreate, unlockSecureVault: unlockSecureVault)
                .tabItem { Label(IceVaultTab.create.rawValue, systemImage: IceVaultTab.create.symbol) }
                .tag(IceVaultTab.create)

            IceVaultSearchView(openEditor: openEditor)
                .tabItem { Label(IceVaultTab.search.rawValue, systemImage: IceVaultTab.search.symbol) }
                .tag(IceVaultTab.search)

            IceVaultSettingsView()
                .tabItem { Label(IceVaultTab.settings.rawValue, systemImage: IceVaultTab.settings.symbol) }
                .tag(IceVaultTab.settings)
        }
        .tint(IceVaultTheme.primary)
        .sheet(item: $editorNote) { note in
            NavigationStack {
                IceVaultNoteEditor(note: note)
            }
        }
        .alert("Ice Vault", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: selectedTab) { tab in
            UserDefaults.standard.set(tab.rawValue, forKey: "iceVaultSelectedTab")
        }
    }

    private func openEditor(_ note: IceVaultNote) {
        if note.isSecure && store.settings.enableFaceID {
            Task {
                if await authenticator.unlock() {
                    editorNote = note
                } else {
                    alertMessage = authenticator.lastError
                }
            }
        } else {
            editorNote = note
        }
    }

    private func quickCreate(_ type: IceVaultNoteType) {
        let vaultId = store.defaultVaultId()
        var checklist: [IceVaultChecklistItem] = []
        if type == .checklist {
            checklist = [
                IceVaultChecklistItem(text: "First goal", isCompleted: false, order: 0),
                IceVaultChecklistItem(text: "Next step", isCompleted: false, order: 1)
            ]
        }
        editorNote = IceVaultNote(
            title: "",
            body: "",
            type: type,
            vaultId: vaultId,
            tags: [],
            isPinned: false,
            isStarred: false,
            isSecure: false,
            reminderDate: nil,
            checklistItems: checklist
        )
    }

    private func unlockSecureVault() {
        Task {
            if await authenticator.unlock(reason: "Open your secure Ice Vault") {
                selectedTab = .search
                alertMessage = store.secureNotes.isEmpty ? "Secure Vault is unlocked. Add a private note by enabling Secure in the editor." : "Secure Vault unlocked. Secure notes are available through Search and Home."
            } else {
                alertMessage = authenticator.lastError
            }
        }
    }
}

struct IceVaultHomeView: View {
    @EnvironmentObject private var store: IceVaultStore
    var openEditor: (IceVaultNote) -> Void
    var quickCreate: (IceVaultNoteType) -> Void
    @State private var appeared = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            IceVaultScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        IceVaultHeader(title: greeting(), subtitle: "What's on your mind today?")
                            .padding(.top, 8)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)

                        quickCapture
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        LazyVGrid(columns: columns, spacing: 12) {
                            statCard("All Notes", "\(store.notes.count)", "doc.text.fill", .blue)
                            statCard("Today's Captures", "\(store.todayCaptureCount)", "calendar.badge.clock", .cyan)
                            statCard("Pinned", "\(store.pinnedNotes.count)", "pin.fill", .orange)
                            statCard("Reminders", "\(store.upcomingReminders.count)", "bell.fill", .purple)
                        }

                        IceVaultHeader(title: "Recent Ideas", subtitle: nil, actionTitle: "View all") {}
                        if store.notes.isEmpty {
                            IceVaultEmptyState(title: "No ideas yet", subtitle: "Use Quick Capture to add your first note, checklist, image, or voice memo.", systemName: "snowflake")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)) { note in
                                    Button {
                                        openEditor(note)
                                    } label: {
                                        IceVaultNoteRow(note: note)
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 90)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        quickCreate(.text)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(IceVaultTheme.vaultGradient, in: Circle())
                            .shadow(color: IceVaultTheme.primary.opacity(0.35), radius: 18, y: 9)
                    }
                    .pressScale()
                    .padding(.trailing, 22)
                    .padding(.bottom, 18)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Capture")
                        .font(.headline.weight(.black))
                        .foregroundStyle(IceVaultTheme.ink)
                    Text("Jot down an idea in a second.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IceVaultTheme.muted)
                }
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(IceVaultTheme.primary)
            }
            HStack(spacing: 10) {
                quickButton(.text, .blue)
                quickButton(.voice, .cyan)
                quickButton(.checklist, .purple)
                quickButton(.photo, .indigo)
            }
        }
        .padding(16)
        .iceCard()
    }

    private func quickButton(_ type: IceVaultNoteType, _ color: Color) -> some View {
        Button {
            quickCreate(type)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.symbol)
                    .font(.system(size: 20, weight: .bold))
                Text(type.title)
                    .font(.caption2.weight(.black))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .pressScale()
    }

    private func statCard(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.black))
                    .foregroundStyle(IceVaultTheme.ink)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IceVaultTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .iceCard()
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}

struct IceVaultVaultsView: View {
    @EnvironmentObject private var store: IceVaultStore
    var openEditor: (IceVaultNote) -> Void
    @State private var editingVault: IceVaultVault?
    @State private var showingNewVault = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            IceVaultScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        IceVaultHeader(title: "My Vaults", subtitle: "Folders, collections & color labels", actionTitle: "+ New") {
                            showingNewVault = true
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.vaults) { vault in
                                NavigationLink {
                                    IceVaultVaultDetailView(vault: vault, openEditor: openEditor)
                                } label: {
                                    vaultCard(vault)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename") { editingVault = vault }
                                    Button("Delete", role: .destructive) { store.deleteVault(vault) }
                                }
                            }
                        }
                        IceVaultPrimaryButton(title: "New Vault", systemName: "plus") {
                            showingNewVault = true
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $editingVault) { vault in
                IceVaultVaultEditor(vault: vault)
            }
            .sheet(isPresented: $showingNewVault) {
                IceVaultVaultEditor(vault: nil)
            }
        }
    }

    private func vaultCard(_ vault: IceVaultVault) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(IceVaultPalette.color(vault.colorName).gradient)
                    Image(systemName: vault.iconName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(IceVaultTheme.muted)
            }
            Text(vault.name)
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack {
                Circle()
                    .fill(IceVaultPalette.color(vault.colorName))
                    .frame(width: 7, height: 7)
                Text("\(store.noteCount(for: vault)) notes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(IceVaultTheme.muted)
                Spacer()
            }
        }
        .padding(16)
        .iceCard()
    }
}

struct IceVaultVaultDetailView: View {
    @EnvironmentObject private var store: IceVaultStore
    var vault: IceVaultVault
    var openEditor: (IceVaultNote) -> Void

    var body: some View {
        IceVaultScreen {
            List {
                ForEach(store.notes(in: vault)) { note in
                    Button {
                        openEditor(note)
                    } label: {
                        IceVaultNoteRow(note: note)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onDelete { indexSet in
                    let notes = store.notes(in: vault)
                    indexSet.map { notes[$0] }.forEach(store.deleteNote)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(vault.name)
        }
    }
}

struct IceVaultVaultEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: IceVaultStore
    @State private var name: String
    @State private var iconName: String
    @State private var colorName: String
    private var vault: IceVaultVault?

    private let icons = ["briefcase.fill", "book.closed.fill", "suitcase.fill", "heart.fill", "fork.knife", "play.rectangle.fill", "person.fill", "laptopcomputer", "sparkles", "snowflake"]

    init(vault: IceVaultVault?) {
        self.vault = vault
        _name = State(initialValue: vault?.name ?? "")
        _iconName = State(initialValue: vault?.iconName ?? "archivebox.fill")
        _colorName = State(initialValue: vault?.colorName ?? "blue")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Vault name", text: $name)
                Picker("Icon", selection: $iconName) {
                    ForEach(icons, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                Section("Color") {
                    HStack {
                        ForEach(IceVaultPalette.colorNames, id: \.self) { color in
                            Button {
                                colorName = color
                            } label: {
                                Circle()
                                    .fill(IceVaultPalette.color(color))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(colorName == color ? IceVaultTheme.ink : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(vault == nil ? "New Vault" : "Edit Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var vault {
                            vault.name = name
                            vault.iconName = iconName
                            vault.colorName = colorName
                            store.updateVault(vault)
                        } else {
                            store.createVault(name: name, iconName: iconName, colorName: colorName)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct IceVaultActionView: View {
    @EnvironmentObject private var store: IceVaultStore
    var openEditor: (IceVaultNote) -> Void
    var quickCreate: (IceVaultNoteType) -> Void
    var unlockSecureVault: () -> Void

    var body: some View {
        NavigationStack {
            IceVaultScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        IceVaultHeader(title: "Create", subtitle: "Turn ideas into action")
                        HStack(spacing: 10) {
                            actionButton("Note", "doc.text.fill", .blue) { quickCreate(.text) }
                            actionButton("Voice", "mic.fill", .cyan) { quickCreate(.voice) }
                            actionButton("Checklist", "checklist.checked", .purple) { quickCreate(.checklist) }
                            actionButton("Photo", "photo.fill", .indigo) { quickCreate(.photo) }
                        }

                        noteSection("Pinned Ideas", notes: Array(store.pinnedNotes.prefix(4)), empty: "Pin a note to keep it at the top.", icon: "pin.fill")
                        remindersSection
                        noteSection("Starred Ideas", notes: Array(store.starredNotes.prefix(4)), empty: "Star notes you want to revisit.", icon: "star.fill")

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(IceVaultTheme.primary)
                                    .frame(width: 58, height: 58)
                                    .background(IceVaultTheme.ice, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Secure Vault")
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(IceVaultTheme.ink)
                                    Text("Your ideas are safe & private.")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(IceVaultTheme.muted)
                                }
                                Spacer()
                            }
                            IceVaultPrimaryButton(title: "Unlock Vault", systemName: "faceid", action: unlockSecureVault)
                        }
                        .padding(16)
                        .iceCard()
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func actionButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .pressScale()
    }

    private func noteSection(_ title: String, notes: [IceVaultNote], empty: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
            if notes.isEmpty {
                Text(empty)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IceVaultTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(IceVaultTheme.ice, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(notes) { note in
                    Button { openEditor(note) } label: {
                        IceVaultNoteRow(note: note)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Reminders")
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
            if store.upcomingReminders.isEmpty {
                Text("Add a reminder date in the editor.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IceVaultTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(IceVaultTheme.ice, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(store.upcomingReminders.prefix(5)) { note in
                    Button { openEditor(note) } label: {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(note.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(IceVaultTheme.ink)
                                if let reminder = note.reminderDate {
                                    Text(reminder.iceVaultReminder)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(IceVaultTheme.muted)
                                }
                            }
                            Spacer()
                            Button {
                                var updated = note
                                updated.reminderDate = nil
                                store.upsertNote(updated)
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .iceCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct IceVaultSearchView: View {
    @EnvironmentObject private var store: IceVaultStore
    var openEditor: (IceVaultNote) -> Void
    @State private var query = ""
    @State private var filter: IceVaultSearchFilter = .all

    private var results: [IceVaultNote] {
        store.search(query, filter: filter)
    }

    private var tags: [String] {
        Array(Set(store.notes.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack {
            IceVaultScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        IceVaultHeader(title: "Find Anything Fast", subtitle: "Smart search, filters & tags")
                        searchField
                        filterChips
                        if !tags.isEmpty {
                            chipSection(title: "Tags", items: tags) { tag in
                                query = tag
                            }
                        }
                        if query.isEmpty && !store.recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Recent Searches")
                                        .font(.headline.weight(.black))
                                    Spacer()
                                    Button("Clear") { store.clearRecentSearches() }
                                        .font(.caption.weight(.bold))
                                }
                                ForEach(store.recentSearches) { recent in
                                    Button {
                                        query = recent.query
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock")
                                            Text(recent.query)
                                            Spacer()
                                            Image(systemName: "xmark")
                                                .font(.caption.weight(.bold))
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(IceVaultTheme.muted)
                                        .padding(.vertical, 6)
                                    }
                                }
                            }
                            .padding(16)
                            .iceCard()
                        }

                        Text(query.isEmpty ? "Top Results" : "Results")
                            .font(.headline.weight(.black))
                            .foregroundStyle(IceVaultTheme.ink)
                        if results.isEmpty {
                            IceVaultEmptyState(title: "Nothing found", subtitle: "Try another word, tag, vault name, or checklist item.", systemName: "magnifyingglass")
                        } else {
                            ForEach(results) { note in
                                Button { openEditor(note) } label: {
                                    IceVaultNoteRow(note: note)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(IceVaultTheme.muted)
            TextField("Search your ideas...", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { store.addRecentSearch(query) }
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(IceVaultTheme.muted)
        }
        .padding(14)
        .iceCard()
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(IceVaultSearchFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.caption.weight(.black))
                            .foregroundStyle(filter == item ? .white : IceVaultTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == item ? IceVaultTheme.primary : IceVaultTheme.ice, in: Capsule())
                    }
                    .pressScale()
                }
            }
        }
    }

    private func chipSection(title: String, items: [String], action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(items, id: \.self) { item in
                        Button { action(item) } label: {
                            Text("#\(item)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(IceVaultTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(IceVaultTheme.ice, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

struct IceVaultSettingsView: View {
    @EnvironmentObject private var store: IceVaultStore
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            IceVaultScreen {
                Form {
                    Section("App theme") {
                        Picker("Theme", selection: $store.settings.appTheme) {
                            Text("Ice Light").tag("Ice Light")
                            Text("Crystal Blue").tag("Crystal Blue")
                        }
                    }
                    Section("Privacy") {
                        Toggle("Enable Face ID", isOn: $store.settings.enableFaceID)
                    }
                    Section("Default vault") {
                        Picker("Default vault", selection: Binding(
                            get: { store.settings.defaultVaultId ?? store.vaults.first?.id },
                            set: { store.settings.defaultVaultId = $0 }
                        )) {
                            ForEach(store.vaults) { vault in
                                Text(vault.name).tag(Optional(vault.id))
                            }
                        }
                    }
                    Section("Data") {
                        if let url = store.exportURL() {
                            ShareLink(item: url) {
                                Label("Export data", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button("Clear recent searches") {
                            store.clearRecentSearches()
                        }
                        Button("Reset local content", role: .destructive) {
                            showingResetAlert = true
                        }
                    }
                    Section("About Ice Vault") {
                        Text("Ice Vault Slot stores ideas, notes, checklists, selected photos, voice memo paths, tags, vaults, reminders, and settings locally on this device.")
                            .font(.footnote)
                            .foregroundStyle(IceVaultTheme.muted)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Settings")
            }
            .alert("Reset local content?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    store.resetLocalData()
                }
            } message: {
                Text("This removes your current local notes, vault changes, searches, and preferences, then restores starter vaults.")
            }
        }
    }
}

struct IceVaultNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: IceVaultStore
    @StateObject private var recorder = IceVaultAudioRecorder()
    @State private var note: IceVaultNote
    @State private var tagText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingReminder = false
    @State private var showingDeleteAlert = false
    @State private var linkText = ""
    @State private var showingLinkField = false

    init(note: IceVaultNote) {
        _note = State(initialValue: note)
        _tagText = State(initialValue: note.tags.joined(separator: ", "))
    }

    var body: some View {
        IceVaultScreen {
            ScrollView {
                VStack(spacing: 16) {
                    titleBlock
                    metadataBlock
                    bodyBlock
                    checklistBlock
                    attachmentBlock
                    reminderBlock
                    toolbarBlock
                }
                .padding(18)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle(note.title.isEmpty ? "New Idea" : "Edit Idea")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    save()
                    dismiss()
                }
                .fontWeight(.bold)
            }
            if store.notes.contains(where: { $0.id == note.id }) {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    note.imageData = data
                    if note.type == .text { note.type = .photo }
                }
            }
        }
        .onChange(of: recorder.lastRecordingURL) { url in
            guard let url else { return }
            note.voiceRecordingURL = url
            if note.type == .text { note.type = .voice }
        }
        .alert("Delete note?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteNote(note)
                dismiss()
            }
        } message: {
            Text("This removes the note and its local voice recording if one exists.")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $note.title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(IceVaultTheme.ink)
            TextEditor(text: $note.body)
                .frame(minHeight: 150)
                .padding(8)
                .background(IceVaultTheme.ice.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .iceCard()
    }

    private var metadataBlock: some View {
        VStack(spacing: 12) {
            Picker("Type", selection: $note.type) {
                ForEach(IceVaultNoteType.allCases) { type in
                    Label(type.title, systemImage: type.symbol).tag(type)
                }
            }
            Picker("Vault", selection: $note.vaultId) {
                ForEach(store.vaults) { vault in
                    Text(vault.name).tag(vault.id)
                }
            }
            TextField("Tags separated by commas", text: $tagText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Toggle("Pin note", isOn: $note.isPinned)
                Toggle("Favorite", isOn: $note.isStarred)
            }
            Toggle("Secure private note", isOn: $note.isSecure)
        }
        .font(.subheadline.weight(.semibold))
        .padding(16)
        .iceCard()
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
            HStack {
                ForEach(parsedTags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(IceVaultTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(IceVaultTheme.ice, in: Capsule())
                }
                if parsedTags.isEmpty {
                    Text("Add tags to make search sharper.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IceVaultTheme.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .iceCard()
    }

    private var checklistBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key Goals")
                    .font(.headline.weight(.black))
                    .foregroundStyle(IceVaultTheme.ink)
                Spacer()
                Button {
                    note.type = .checklist
                    note.checklistItems.append(IceVaultChecklistItem(text: "", isCompleted: false, order: note.checklistItems.count))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            if note.checklistItems.isEmpty {
                Text("Add checklist items for tasks, packing lists, or launch steps.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IceVaultTheme.muted)
            } else {
                ForEach($note.checklistItems) { $item in
                    HStack {
                        Button {
                            item.isCompleted.toggle()
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : IceVaultTheme.muted)
                        }
                        TextField("Goal", text: $item.text)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .iceCard()
    }

    private var attachmentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(.headline.weight(.black))
                .foregroundStyle(IceVaultTheme.ink)
            if let imageData = note.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let voiceURL = note.voiceRecordingURL {
                Label(voiceURL.lastPathComponent, systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(IceVaultTheme.muted)
                    .lineLimit(1)
            }
            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Image", systemImage: "photo")
                }
                Button {
                    recorder.toggleRecording()
                } label: {
                    Label(recorder.isRecording ? "Stop" : "Voice", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                Spacer()
            }
            .font(.subheadline.weight(.bold))
            if let error = recorder.errorMessage {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .iceCard()
    }

    private var reminderBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Reminder", isOn: Binding(
                get: { note.reminderDate != nil },
                set: { enabled in
                    note.reminderDate = enabled ? (note.reminderDate ?? Calendar.current.date(byAdding: .hour, value: 2, to: Date())) : nil
                }
            ))
            if note.reminderDate != nil {
                DatePicker("Reminder date", selection: Binding(
                    get: { note.reminderDate ?? Date() },
                    set: { note.reminderDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(16)
        .iceCard()
    }

    private var toolbarBlock: some View {
        VStack(spacing: 12) {
            if showingLinkField {
                HStack {
                    TextField("Paste link", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") {
                        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            note.body += note.body.isEmpty ? trimmed : "\n\(trimmed)"
                            linkText = ""
                        }
                        showingLinkField = false
                    }
                    .fontWeight(.bold)
                }
                .padding(12)
                .background(IceVaultTheme.ice, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack {
                editorTool("bold", "bold") { wrapSelection(marker: "**") }
                editorTool("italic", "italic") { wrapSelection(marker: "_") }
                editorTool("checklist", "checklist") {
                    note.type = .checklist
                    note.checklistItems.append(IceVaultChecklistItem(text: "", isCompleted: false, order: note.checklistItems.count))
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                }
                .frame(width: 36, height: 36)
                editorTool("link", "link") { showingLinkField.toggle() }
                editorTool("reminder", "bell") {
                    note.reminderDate = note.reminderDate ?? Calendar.current.date(byAdding: .hour, value: 2, to: Date())
                }
                editorTool("vault", "archivebox") {}
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(IceVaultTheme.ink)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .iceCard()
    }

    private func editorTool(_ title: String, _ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 36, height: 36)
                .background(IceVaultTheme.ice, in: Circle())
        }
        .accessibilityLabel(title)
        .pressScale()
    }

    private var parsedTags: [String] {
        tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func wrapSelection(marker: String) {
        if note.body.isEmpty {
            note.body = "\(marker)important\(marker)"
        } else {
            note.body += " \(marker)text\(marker)"
        }
    }

    private func save() {
        note.tags = parsedTags
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.title = note.type == .checklist ? "New checklist" : "Untitled idea"
        }
        store.upsertNote(note)
    }
}
