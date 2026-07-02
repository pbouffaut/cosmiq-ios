import SwiftUI

/// Animated field of rising bubbles, used by the splash screen and as hero
/// decoration. Drawn in a single Canvas at a capped frame rate — one
/// Metal-backed layer, no per-bubble view animations, so it stays cheap even
/// inside scrolling lists.
struct BubbleField: View {
    var bubbleCount = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<bubbleCount {
                    // Deterministic pseudo-random parameters per bubble.
                    let jitter = Double((index * 37) % 13) / 13.0
                    let radius = 3.0 + jitter * 11.0
                    let speed = 26.0 + jitter * 46.0 // points per second
                    let travel = size.height + radius * 4
                    let phase = Double(index) / Double(max(bubbleCount, 1)) * 1.7 + jitter
                    let progress = ((time * speed / travel) + phase).truncatingRemainder(dividingBy: 1.0)

                    let y = size.height + radius * 2 - progress * travel
                    let baseX = ((Double(index) / Double(max(bubbleCount, 1))) + jitter * 0.4)
                        .truncatingRemainder(dividingBy: 1.0) * size.width
                    let x = baseX + sin(time * 0.8 + phase * 6) * (jitter - 0.5) * 30

                    let opacity = 0.55 * (1.0 - progress * 0.8)
                    let rect = CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.stroke(Circle().path(in: rect),
                                   with: .color(Color.foam.opacity(opacity)),
                                   lineWidth: max(1.2, radius * 0.16))
                }
            }
        }
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
