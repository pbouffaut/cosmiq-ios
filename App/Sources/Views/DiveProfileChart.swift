import Charts
import CosmiqKit
import SwiftUI

/// The dive profile with a draggable scrubber: a vertical line that snaps to
/// the nearest sample and reports depth, temperature and vertical speed at
/// that moment. (The COSMIQ+ records only time/depth/temperature per sample —
/// no-deco data is not stored in the dive log.)
struct DiveProfileChart: View {
    let dive: Dive
    var showsScrubHint = true

    @State private var selectedTime: Int?

    /// Profile without the flat post-surfacing tail the device records.
    private var samples: [DiveSample] { dive.trimmedSamples }

    private var maxDepth: Double { samples.map(\.depth).max() ?? 0 }
    private var lastMinute: Double { Double(samples.last?.time ?? 60) / 60.0 }

    private var selectedIndex: Int? {
        guard let selectedTime, !samples.isEmpty else { return nil }
        return samples.indices.min {
            abs(samples[$0].time - selectedTime) < abs(samples[$1].time - selectedTime)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            infoBar
            chart
        }
    }

    // MARK: Readout

    @ViewBuilder
    private var infoBar: some View {
        if let index = selectedIndex {
            let sample = samples[index]
            HStack(spacing: 0) {
                readout(Self.clock(sample.time), "time", "clock")
                readout(String(format: "%.1f m", sample.depth), "depth", "arrow.down.to.line")
                readout(String(format: "%.1f °C", sample.temperature), "temp", "thermometer.medium")
                readout(verticalSpeed(at: index), "speed", "arrow.up.arrow.down")
            }
            .padding(.vertical, 8)
            .background(Theme.seaGradient, in: RoundedRectangle(cornerRadius: 10))
        } else if showsScrubHint {
            Label("Touch and drag the profile to explore the dive",
                  systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private func readout(_ value: String, _ caption: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.foam)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    /// Vertical speed around the selected sample, in m/min. ↓ descending.
    private func verticalSpeed(at index: Int) -> String {
        guard index > 0 else { return "—" }
        let current = samples[index]
        let previous = samples[index - 1]
        let dt = Double(current.time - previous.time)
        guard dt > 0 else { return "—" }
        let rate = (current.depth - previous.depth) / dt * 60 // m/min, + = down
        if abs(rate) < 0.05 { return "level" }
        return String(format: "%@ %.1f m/min", rate > 0 ? "↓" : "↑", abs(rate))
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(samples, id: \.time) { sample in
                AreaMark(
                    x: .value("Time", Double(sample.time) / 60.0),
                    y: .value("Depth", -max(0, sample.depth))
                )
                .foregroundStyle(Theme.profileGradient)
                LineMark(
                    x: .value("Time", Double(sample.time) / 60.0),
                    y: .value("Depth", -max(0, sample.depth))
                )
                .foregroundStyle(Color.aqua)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            if let index = selectedIndex {
                let sample = samples[index]
                RuleMark(x: .value("Time", Double(sample.time) / 60.0))
                    .foregroundStyle(Color.foam.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                PointMark(
                    x: .value("Time", Double(sample.time) / 60.0),
                    y: .value("Depth", -max(0, sample.depth))
                )
                .symbolSize(90)
                .foregroundStyle(Color.foam)
            }
        }
        .chartXScale(domain: 0...max(lastMinute, 1))
        .chartYScale(domain: (-(maxDepth * 1.08))...0)
        .chartXAxisLabel("minutes")
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let depth = value.as(Double.self) {
                        Text("\(-depth, specifier: "%.0f") m")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geometry[plotFrame].origin.x
                                if let minutes: Double = proxy.value(atX: x) {
                                    selectedTime = Int(minutes * 60)
                                }
                            }
                    )
            }
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Full-screen profile, shown on tap or when the phone rotates to landscape.
struct DiveProfileFullScreenView: View {
    let dive: Dive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DiveProfileChart(dive: dive, showsScrubHint: false)
                .padding()
                .navigationTitle(dive.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
