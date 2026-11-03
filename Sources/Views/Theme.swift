import SwiftUI

enum Theme {
    static let accent = Color(red: 0.41, green: 0.48, blue: 1.0)
    static let accentSecondary = Color(red: 0.78, green: 0.42, blue: 0.98)
    static let background = Color(red: 0.035, green: 0.04, blue: 0.06)
    static let surface = Color(red: 0.075, green: 0.085, blue: 0.115)
    static let surfaceRaised = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.62, green: 0.65, blue: 0.72)
    static let success = Color(red: 0.29, green: 0.84, blue: 0.55)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.42)

    static let brandGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardRadius: CGFloat = 22
}

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: value)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func host(_ url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.black.opacity(enabled ? 0.9 : 0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
