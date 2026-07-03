import CosmiqKit
import SwiftUI
import UniformTypeIdentifiers

struct LogbookView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager
    @EnvironmentObject private var logbook: Logbook

    @State private var syncProgress: DiveSyncProgress?
    @State private var syncError: String?
    @State private var lastSyncCount: Int?
    @State private var candidates: [DiveCandidate] = []
    @State private var showPicker = false
    @State private var showFileImporter = false

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
                                     : "Added \(count) new dive\(count == 1 ? "" : "s")",
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
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import UDDF File…", systemImage: "square.and.arrow.down")
                    }
                    if !logbook.dives.isEmpty {
                        ShareLink(
                            item: UDDFFile(dives: logbook.dives),
                            preview: SharePreview("CosmiQ Logbook.uddf")
                        ) {
                            Label("Export Logbook (UDDF)", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
        .sheet(isPresented: $showPicker) {
            DiveImportPicker(candidates: candidates) { picked in
                download(picked)
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: uddfTypes) { result in
            importUDDF(result)
        }
    }

    private var uddfTypes: [UTType] {
        var types: [UTType] = [.xml]
        if let uddf = UTType(filenameExtension: "uddf") { types.insert(uddf, at: 0) }
        return types
    }

    // MARK: Device sync (phase 1: list, phase 2: download selection)

    private func sync() {
        syncError = nil
        lastSyncCount = nil
        syncProgress = DiveSyncProgress(phase: "Starting…", fraction: 0)
        let session = CosmiqSession(ble: ble)
        Task {
            do {
                let found = try await session.fetchNewDiveSummaries(
                    knownFingerprints: logbook.fingerprints
                ) { progress in
                    syncProgress = progress
                }
                syncProgress = nil
                if found.isEmpty {
                    lastSyncCount = 0
                } else {
                    candidates = found
                    showPicker = true
                }
            } catch {
                syncProgress = nil
                syncError = error.localizedDescription
            }
        }
    }

    private func download(_ picked: [DiveCandidate]) {
        guard !picked.isEmpty else { return }
        syncProgress = DiveSyncProgress(phase: "Starting download…", fraction: 0)
        let session = CosmiqSession(ble: ble)
        Task {
            defer { syncProgress = nil }
            do {
                let dives = try await session.downloadProfiles(for: picked) { progress in
                    syncProgress = progress
                }
                logbook.add(dives)
                lastSyncCount = dives.count
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    // MARK: UDDF file import

    private func importUDDF(_ result: Result<URL, Error>) {
        syncError = nil
        lastSyncCount = nil
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let imported = try UDDFImporter.parse(data: data)
            let fresh = imported.filter {
                !logbook.fingerprints.contains($0.fingerprint) && !logbook.containsSimilar($0)
            }
            logbook.add(fresh)
            lastSyncCount = fresh.count
        } catch {
            syncError = "UDDF import failed: \(error.localizedDescription)"
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
