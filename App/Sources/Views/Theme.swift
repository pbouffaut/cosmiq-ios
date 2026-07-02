import SwiftUI

/// CosmiQ Companion's ocean palette. Depth-ordered: foam is the surface
/// sparkle, abyss the bottom of the sea.
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static let foam = Color(hex: 0x7DF9E4)
    static let aqua = Color(hex: 0x0FB8CE)
    static let ocean = Color(hex: 0x0A7EA3)
    static let oceanDeep = Color(hex: 0x0B4F6C)
    static let abyss = Color(hex: 0x082436)
}

enum Theme {
    /// Surface-to-depth backdrop for hero areas.
    static let seaGradient = LinearGradient(
        colors: [.ocean, .oceanDeep, .abyss],
        startPoint: .top, endPoint: .bottom
    )

    /// Accent sweep for icons and highlights.
    static let accentGradient = LinearGradient(
        colors: [.foam, .aqua],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Fill under the dive-profile line.
    static let profileGradient = LinearGradient(
        colors: [Color.aqua.opacity(0.45), Color.oceanDeep.opacity(0.05)],
        startPoint: .top, endPoint: .bottom
    )
}

/// Round badge with a gradient background, used for list icons and stats.
struct SeaBadge: View {
    let systemImage: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accentGradient.opacity(0.9), in: Circle())
            .background(Circle().fill(Color.oceanDeep))
    }
}

/// One big stat (value + caption) for the dive header card.
struct StatBlock: View {
    let value: String
    let caption: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(Color.foam)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}
