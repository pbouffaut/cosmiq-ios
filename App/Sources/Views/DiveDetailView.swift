import Charts
import CosmiqKit
import SwiftUI

struct DiveDetailView: View {
    let dive: Dive

    var body: some View {
        List {
            if !dive.samples.isEmpty {
                Section("Profile") {
                    Chart(dive.samples, id: \.time) { sample in
                        AreaMark(
                            x: .value("Time", Double(sample.time) / 60.0),
                            y: .value("Depth", -sample.depth)
                        )
                        .foregroundStyle(.blue.opacity(0.25))
                        LineMark(
                            x: .value("Time", Double(sample.time) / 60.0),
                            y: .value("Depth", -sample.depth)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    }
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
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 16))
                }
            }

            Section("Summary") {
                LabeledContent("Date",
                    value: dive.start.map { $0.formatted(date: .long, time: .shortened) } ?? "Unknown")
                LabeledContent("Mode", value: dive.activity.label)
                LabeledContent("Duration", value: DiveRow.durationText(dive.duration))
                LabeledContent("Max Depth", value: String(format: "%.1f m", dive.maxDepth))
                if let temperature = dive.averageTemperature {
                    LabeledContent("Avg Temperature", value: String(format: "%.1f °C", temperature))
                }
                if dive.activity == .scuba {
                    LabeledContent("Gas", value: dive.oxygenPercent == 21 ? "Air" : "EAN\(dive.oxygenPercent)")
                }
                LabeledContent("Surface Pressure", value: "\(dive.atmosphericMillibar) mbar")
                LabeledContent("Sample Interval", value: "\(dive.sampleIntervalSeconds) s")
            }

            Section("Export") {
                ShareLink(item: CSVFile(dive: dive), preview: SharePreview("dive.csv")) {
                    Label("Export CSV", systemImage: "tablecells")
                }
                ShareLink(item: UDDFFile(dives: [dive]), preview: SharePreview("dive.uddf")) {
                    Label("Export UDDF (Subsurface, MacDive)", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(dive.start.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Dive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
