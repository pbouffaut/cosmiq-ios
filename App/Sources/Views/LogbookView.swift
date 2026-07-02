import CosmiqKit
import SwiftUI

struct LogbookView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager
    @EnvironmentObject private var logbook: Logbook

    @State private var syncProgress: DiveSyncProgress?
    @State private var syncError: String?
    @State private var lastSyncCount: Int?

    var body: some View {
        List {
            if let progress = syncProgress {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.phase).font(.callout)
                        ProgressView(value: progress.fraction)
                    }
                }
            }
            if let error = syncError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            if let count = lastSyncCount {
                Section {
                    Label(count == 0 ? "Logbook already up to date"
                                     : "Downloaded \(count) new dive\(count == 1 ? "" : "s")",
                          systemImage: count == 0 ? "checkmark.circle" : "square.and.arrow.down")
                        .foregroundStyle(.green)
                }
            }

            Section {
                ForEach(logbook.dives) { dive in
                    NavigationLink(value: dive) {
                        DiveRow(dive: dive)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        logbook.delete(logbook.dives[index])
                    }
                }
            } footer: {
                if !logbook.dives.isEmpty {
                    Text("\(logbook.dives.count) dives · stored on this iPhone")
                }
            }
        }
        .navigationTitle("Logbook")
        .navigationDestination(for: Dive.self) { dive in
            DiveDetailView(dive: dive)
        }
        .overlay {
            if logbook.dives.isEmpty && syncProgress == nil {
                ContentUnavailableView(
                    "No dives yet",
                    systemImage: "water.waves",
                    description: Text(ble.state.isConnected
                        ? "Tap Sync to download dives from your COSMIQ+."
                        : "Connect your COSMIQ+ on the Device tab, then sync your dives here.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !logbook.dives.isEmpty {
                    ShareLink(
                        item: UDDFFile(dives: logbook.dives),
                        preview: SharePreview("CosmiQ Logbook.uddf")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sync()
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!ble.state.isConnected || syncProgress != nil)
            }
        }
    }

    private func sync() {
        syncError = nil
        lastSyncCount = nil
        syncProgress = DiveSyncProgress(phase: "Starting…", fraction: 0)
        let session = CosmiqSession(ble: ble)
        Task {
            defer { syncProgress = nil }
            do {
                let dives = try await session.downloadDives(
                    knownFingerprints: logbook.fingerprints
                ) { progress in
                    syncProgress = progress
                }
                logbook.add(dives)
                lastSyncCount = dives.count
            } catch {
                syncError = error.localizedDescription
            }
        }
    }
}

struct DiveRow: View {
    let dive: Dive

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dive.activity == .freedive ? "figure.pool.swim" : "water.waves")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(dive.start.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unknown date")
                    .font(.headline)
                Text("\(dive.activity.label) · \(Self.durationText(dive.duration)) · max \(dive.maxDepth, specifier: "%.1f") m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func durationText(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}

/// Transferable wrapper so ShareLink can hand out a .uddf file.
struct UDDFFile: Transferable {
    let dives: [Dive]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .xml) { file in
            Data(DiveExporter.uddf(for: file.dives).utf8)
        }
        .suggestedFileName("CosmiQ Logbook.uddf")
    }
}

struct CSVFile: Transferable {
    let dive: Dive

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(DiveExporter.csv(for: file.dive).utf8)
        }
        .suggestedFileName("dive.csv")
    }
}
