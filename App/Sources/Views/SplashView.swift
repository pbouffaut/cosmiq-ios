import SwiftUI

/// Animated field of rising bubbles, used by the splash screen and as hero
/// decoration.
struct BubbleField: View {
    struct Bubble: Identifiable {
        let id: Int
        let x: CGFloat        // 0...1 horizontal position
        let size: CGFloat
        let duration: Double
        let delay: Double
        let drift: CGFloat
    }

    var bubbleCount = 14
    @State private var rising = false

    private var bubbles: [Bubble] {
        // Deterministic pseudo-random layout so the view is stable.
        (0..<bubbleCount).map { index in
            let fraction = CGFloat(index) / CGFloat(bubbleCount)
            let jitter = CGFloat((index * 37 % 13)) / 13.0
            return Bubble(
                id: index,
                x: (fraction + jitter * 0.4).truncatingRemainder(dividingBy: 1.0),
                size: 6 + jitter * 22,
                duration: 3.2 + Double(jitter) * 3.5,
                delay: Double(index) * 0.35,
                drift: (jitter - 0.5) * 40
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(bubbles) { bubble in
                Circle()
                    .strokeBorder(Color.foam.opacity(0.5), lineWidth: max(1.5, bubble.size * 0.12))
                    .background(Circle().fill(Color.foam.opacity(0.08)))
                    .frame(width: bubble.size, height: bubble.size)
                    .position(x: bubble.x * geometry.size.width + (rising ? bubble.drift : 0),
                              y: rising ? -bubble.size : geometry.size.height + bubble.size)
                    .opacity(rising ? 0.0 : 0.9)
                    .animation(
                        .linear(duration: bubble.duration)
                        .repeatForever(autoreverses: false)
                        .delay(bubble.delay),
                        value: rising
                    )
            }
        }
        .onAppear { rising = true }
        .allowsHitTesting(false)
    }
}

/// First thing shown when the app boots: matches the static launch screen
/// color, then animates bubbles while the UI warms up.
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.seaGradient.ignoresSafeArea()
            BubbleField()
            VStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.foam)
                Text("COSMIQ")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(4)
                Text("back from the abyss")
                    .font(.title3.weight(.medium).italic())
                    .foregroundStyle(Color.foam)
            }
        }
    }
}

#Preview {
    SplashView()
}
