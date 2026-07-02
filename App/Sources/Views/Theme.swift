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

/// The app's branded header: sea gradient, rising bubbles, COSMIQ wordmark.
/// Used as the "title bar" of the Device panel and the About page.
struct SeaBanner: View {
    var subtitle = "back from the abyss"
    var status: String? = nil
    var animateIcon = false
    var bubbleCount = 9
    var compact = false

    var body: some View {
        ZStack {
            Theme.seaGradient
            BubbleField(bubbleCount: bubbleCount)
            VStack(spacing: compact ? 5 : 8) {
                Image(systemName: "water.waves")
                    .font(.system(size: compact ? 26 : 36, weight: .semibold))
                    .foregroundStyle(Color.foam)
                    .symbolEffect(.variableColor.iterative, isActive: animateIcon)
                Text("COSMIQ")
                    .font(.system(size: compact ? 24 : 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(3)
                Text(subtitle)
                    .font(.callout.weight(.medium).italic())
                    .foregroundStyle(Color.foam)
                if let status {
                    Label(status, systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .labelStyle(StatusChipStyle())
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, compact ? 20 : 30)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private struct StatusChipStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                configuration.title
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.white.opacity(0.15), in: Capsule())
        }
    }
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
