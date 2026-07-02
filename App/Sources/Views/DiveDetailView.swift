import Charts
import CoreLocation
import CosmiqKit
import MapKit
import SwiftUI

struct DiveDetailView: View {
    @EnvironmentObject private var logbook: Logbook
    @State private var showEditor = false

    /// Snapshot handed in by navigation; the live version comes from the
    /// logbook so metadata edits show immediately.
    let dive: Dive

    private var current: Dive { logbook.dive(withID: dive.id) ?? dive }

    var body: some View {
        List {
            heroSection

            if !current.samples.isEmpty {
                profileSection
            }

            if let coordinate = current.coordinate {
                mapSection(coordinate)
            }

            if let notes = current.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            detailsSection
            exportSection
        }
        .navigationTitle(current.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            DiveEditView(dive: current)
        }
    }

    // MARK: Sections

    private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.displayTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        if let date = current.effectiveDate {
                            Text(date.formatted(date: .long, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        if let site = current.siteName, !site.isEmpty, current.name != nil {
                            Label(site, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(Color.foam)
                        }
                    }
                    Spacer()
                    SeaBadge(systemImage: current.activity == .freedive
                             ? "figure.pool.swim" : "water.waves", size: 44)
                }

                HStack(spacing: 8) {
                    StatBlock(value: String(format: "%.1f m", current.maxDepth),
                              caption: "max depth", systemImage: "arrow.down.to.line")
                    StatBlock(value: DiveRow.durationText(current.duration),
                              caption: "duration", systemImage: "timer")
                    if let temperature = current.averageTemperature {
                        StatBlock(value: String(format: "%.0f °C", temperature),
                                  caption: "avg temp", systemImage: "thermometer.medium")
                    }
                    StatBlock(value: current.activity == .scuba && current.oxygenPercent != 21
                              ? "EAN\(current.oxygenPercent)"
                              : current.activity == .scuba ? "Air" : current.activity.label,
                              caption: current.activity == .scuba ? "gas" : "mode",
                              systemImage: "lungs.fill")
                }
            }
            .padding(18)
            .background(Theme.seaGradient, in: RoundedRectangle(cornerRadius: 16))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var profileSection: some View {
        Section("Dive Profile") {
            Chart(current.samples, id: \.time) { sample in
                AreaMark(
                    x: .value("Time", Double(sample.time) / 60.0),
                    y: .value("Depth", -sample.depth)
                )
                .foregroundStyle(Theme.profileGradient)
                LineMark(
                    x: .value("Time", Double(sample.time) / 60.0),
                    y: .value("Depth", -sample.depth)
                )
                .foregroundStyle(Color.aqua)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
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

    private func mapSection(_ coordinate: (latitude: Double, longitude: Double)) -> some View {
        Section("Dive Site") {
            let center = CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                longitude: coordinate.longitude)
            MapSnapshotView(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Button {
                let placemark = MKPlacemark(coordinate: center)
                let item = MKMapItem(placemark: placemark)
                item.name = current.siteName ?? current.displayTitle
                item.openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Mode", value: current.activity.label)
            if current.userDate != nil, let recorded = current.start {
                LabeledContent("Computer Time",
                               value: recorded.formatted(date: .abbreviated, time: .shortened))
            }
            LabeledContent("Surface Pressure", value: "\(current.atmosphericMillibar) mbar")
            LabeledContent("Sample Interval", value: "\(current.sampleIntervalSeconds) s")
        }
    }

    private var exportSection: some View {
        Section("Export") {
            ShareLink(item: CSVFile(dive: current), preview: SharePreview("dive.csv")) {
                Label("Export CSV", systemImage: "tablecells")
            }
            ShareLink(item: UDDFFile(dives: [current]), preview: SharePreview("dive.uddf")) {
                Label("Export UDDF (Subsurface, MacDive)", systemImage: "square.and.arrow.up")
            }
        }
    }
}
