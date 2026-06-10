import SwiftUI

enum IceVaultTheme {
    static let ink = Color(red: 0.05, green: 0.10, blue: 0.20)
    static let muted = Color(red: 0.38, green: 0.48, blue: 0.61)
    static let primary = Color(red: 0.05, green: 0.42, blue: 0.95)
    static let sky = Color(red: 0.53, green: 0.82, blue: 1.0)
    static let ice = Color(red: 0.91, green: 0.97, blue: 1.0)
    static let surface = Color.white.opacity(0.92)
    static let line = Color(red: 0.79, green: 0.88, blue: 0.97)

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.99, blue: 1.0),
                Color(red: 0.87, green: 0.95, blue: 1.0),
                Color(red: 0.98, green: 0.99, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var vaultGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.23, blue: 0.62), Color(red: 0.0, green: 0.66, blue: 1.0), Color(red: 0.75, green: 0.95, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct IceVaultCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(IceVaultTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: Color.blue.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func iceCard() -> some View {
        modifier(IceVaultCardStyle())
    }

    func pressScale() -> some View {
        buttonStyle(IceVaultPressStyle())
    }
}

struct IceVaultPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension Date {
    var iceVaultShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var iceVaultReminder: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
