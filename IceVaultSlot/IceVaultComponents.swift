import SwiftUI

struct IceVaultScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            IceVaultTheme.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.light)
    }
}

struct IceVaultHeader: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(IceVaultTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(IceVaultTheme.muted)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IceVaultTheme.primary)
            }
        }
    }
}

struct IceVaultPrimaryButton: View {
    var title: String
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(IceVaultTheme.vaultGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: IceVaultTheme.primary.opacity(0.28), radius: 18, x: 0, y: 10)
        }
        .pressScale()
    }
}

struct IceVaultNoteRow: View {
    @EnvironmentObject private var store: IceVaultStore
    var note: IceVaultNote

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(IceVaultPalette.color(store.vault(for: note.vaultId)?.colorName ?? "blue").opacity(0.15))
                Image(systemName: note.type.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(IceVaultPalette.color(store.vault(for: note.vaultId)?.colorName ?? "blue"))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(note.title.isEmpty ? "Untitled idea" : note.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(IceVaultTheme.ink)
                        .lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    if note.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(IceVaultTheme.primary)
                    }
                }
                Text(note.body.isEmpty ? note.checklistItems.map(\.text).joined(separator: ", ") : note.body)
                    .font(.caption)
                    .foregroundStyle(IceVaultTheme.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(store.vault(for: note.vaultId)?.name ?? "Vault")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(IceVaultTheme.ice, in: Capsule())
                    Text(note.updatedAt.iceVaultShort)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(IceVaultTheme.muted)
                }
            }
            Spacer()
            if note.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(12)
        .iceCard()
    }
}

struct IceVaultEmptyState: View {
    var title: String
    var subtitle: String
    var systemName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(IceVaultTheme.primary)
                .frame(width: 74, height: 74)
                .background(IceVaultTheme.ice, in: Circle())
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(IceVaultTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(IceVaultTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .iceCard()
    }
}
