import CosmiqKit
import Foundation
import os

/// Persistent logbook.
///
/// Dives live in `logbook.json`. When iCloud Drive is available the file of
/// record moves into the app's private iCloud container — so the logbook
/// survives deleting the app and follows the user to a new iPhone — with the
/// local Documents copy kept as an always-available cache. On startup the two
/// are merged by dive fingerprint, preferring whichever copy carries more
/// user metadata.
@MainActor
final class Logbook: ObservableObject {
    @Published private(set) var dives: [Dive] = []
    /// True once the iCloud container is active and holds the file of record.
    @Published private(set) var storedInICloud = false

    private let log = Logger(subsystem: "com.pbouffaut.CosmiqCompanion", category: "logbook")
    private let localURL: URL
    private var cloudURL: URL?

    var fingerprints: Set<String> { Set(dives.map(\.fingerprint)) }

    init(fileURL: URL? = nil) {
        localURL = fileURL ?? URL.documentsDirectory.appending(path: "logbook.json")
        dives = Self.read(from: localURL) ?? []
        sortDives()
        if fileURL == nil {
            Task { await activateICloud() }
        }
    }

    // MARK: Mutations

    func add(_ newDives: [Dive]) {
        let known = fingerprints
        let unique = newDives.filter { !known.contains($0.fingerprint) }
        guard !unique.isEmpty else { return }
        dives.append(contentsOf: unique)
        sortDives()
        save()
    }

    func delete(_ dive: Dive) {
        dives.removeAll { $0.fingerprint == dive.fingerprint }
        save()
    }

    /// Replace the stored dive with the same fingerprint (metadata edits).
    func update(_ dive: Dive) {
        guard let index = dives.firstIndex(where: { $0.fingerprint == dive.fingerprint }) else { return }
        dives[index] = dive
        sortDives()
        save()
    }

    func dive(withID id: String) -> Dive? {
        dives.first { $0.fingerprint == id }
    }

    // MARK: iCloud

    private func activateICloud() async {
        // url(forUbiquityContainerIdentifier:) can block; never call it on main.
        let container = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        guard let container else {
            log.info("iCloud unavailable; logbook stays local")
            return
        }

        let documents = container.appending(path: "Documents")
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let fileURL = documents.appending(path: "logbook.json")

        // A not-yet-downloaded iCloud file shows up as a ".name.icloud"
        // placeholder. If either form exists we must wait for the real bytes
        // before writing anything, or a reinstall could clobber the cloud copy.
        let placeholder = documents.appending(path: ".logbook.json.icloud")
        let cloudHasFile = FileManager.default.fileExists(atPath: fileURL.path)
            || FileManager.default.fileExists(atPath: placeholder.path)

        var cloudDives: [Dive] = []
        if cloudHasFile {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            for _ in 0..<30 {
                if let existing = Self.read(from: fileURL) {
                    cloudDives = existing
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            if cloudDives.isEmpty && Self.read(from: fileURL) == nil {
                log.warning("iCloud logbook exists but did not download; staying local this launch")
                return
            }
        }

        cloudURL = fileURL
        storedInICloud = true
        merge(cloudDives)
        save()
        log.info("iCloud logbook active (\(self.dives.count) dives after merge)")
    }

    /// Union by fingerprint; on conflict keep the copy with more user metadata.
    private func merge(_ incoming: [Dive]) {
        func metadataScore(_ dive: Dive) -> Int {
            [dive.name != nil, dive.siteName != nil, dive.notes != nil,
             dive.latitude != nil, dive.userDate != nil].filter { $0 }.count
        }
        var byFingerprint = Dictionary(dives.map { ($0.fingerprint, $0) },
                                       uniquingKeysWith: { first, _ in first })
        for dive in incoming {
            if let local = byFingerprint[dive.fingerprint] {
                byFingerprint[dive.fingerprint] =
                    metadataScore(dive) > metadataScore(local) ? dive : local
            } else {
                byFingerprint[dive.fingerprint] = dive
            }
        }
        dives = Array(byFingerprint.values)
        sortDives()
    }

    // MARK: Persistence

    private func sortDives() {
        dives.sort { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
    }

    private static func read(from url: URL) -> [Dive]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Dive].self, from: data)
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(dives)
            // Local copy always, as cache and offline fallback.
            try data.write(to: localURL, options: .atomic)
            if let cloudURL {
                try data.write(to: cloudURL, options: .atomic)
            }
        } catch {
            log.error("Failed to save logbook: \(error.localizedDescription)")
        }
    }
}
