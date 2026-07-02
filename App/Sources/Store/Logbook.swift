import CosmiqKit
import Foundation
import os

/// Persistent local logbook: dives stored as JSON in the app's Documents
/// directory (visible in the Files app thanks to the Info.plist flags).
@MainActor
final class Logbook: ObservableObject {
    @Published private(set) var dives: [Dive] = []

    private let log = Logger(subsystem: "com.pbouffaut.CosmiqCompanion", category: "logbook")
    private let fileURL: URL

    var fingerprints: Set<String> { Set(dives.map(\.fingerprint)) }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.documentsDirectory.appending(path: "logbook.json")
        load()
    }

    func add(_ newDives: [Dive]) {
        let known = fingerprints
        let unique = newDives.filter { !known.contains($0.fingerprint) }
        guard !unique.isEmpty else { return }
        dives.append(contentsOf: unique)
        sortAndSave()
    }

    func delete(_ dive: Dive) {
        dives.removeAll { $0.fingerprint == dive.fingerprint }
        save()
    }

    private func sortAndSave() {
        dives.sort { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            dives = try JSONDecoder().decode([Dive].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            // First launch.
        } catch {
            log.error("Failed to load logbook: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(dives)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to save logbook: \(error.localizedDescription)")
        }
    }
}
