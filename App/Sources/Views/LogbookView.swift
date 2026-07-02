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
                    Label(
                        "\(logbook.dives.count) dives · \(logbook.storedInICloud ? "synced to your iCloud Drive" : "stored on this iPhone")",
                        systemImage: logbook.storedInICloud ? "icloud.fill" : "internaldrive"
                    )
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
                        : "Your logbook lives here, connected or not. To add dives, connect your COSMIQ+ on the Device tab and tap Sync.")
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
            SeaBadge(systemImage: dive.activity == .freedive ? "figure.pool.swim" : "water.waves")
            VStack(alignment: .leading, spacing: 3) {
                Text(dive.displayTitle)
                    .font(.headline)
                if dive.name != nil || dive.siteName != nil,
                   let date = dive.effectiveDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(String(format: "%.1f m", dive.maxDepth), systemImage: "arrow.down.to.line")
                    Label(Self.durationText(dive.duration), systemImage: "timer")
                    if dive.coordinate != nil {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.aqua)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
