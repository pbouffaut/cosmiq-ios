import CosmiqKit
import SwiftUI

/// Dives waiting for the user's selection before entering the logbook —
/// either found on the device during sync, or parsed from a UDDF file.
struct PendingImport: Identifiable {
    enum Source {
        case device([DiveCandidate])
        case file([Dive])
    }

    let id = UUID()
    let source: Source

    /// What the picker shows: header-only summaries for device dives, the
    /// full parsed dives for file imports.
    var summaries: [Dive] {
        switch source {
        case .device(let candidates): return candidates.map(\.summary)
        case .file(let dives): return dives
        }
    }

    var sourceDescription: String {
        switch source {
        case .device: return "on the device"
        case .file: return "in the file"
        }
    }
}

/// Selection sheet shown before any import: only dives that aren't in the
/// logbook yet, all pre-selected.
struct DiveImportPicker: View {
    let pending: PendingImport
    let onImport: ([Dive]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String>

    init(pending: PendingImport, onImport: @escaping ([Dive]) -> Void) {
        self.pending = pending
        self.onImport = onImport
        _selection = State(initialValue: Set(pending.summaries.map(\.fingerprint)))
    }

    private var dives: [Dive] { pending.summaries }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(dives) { dive in
                        Button {
                            toggle(dive.fingerprint)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(dive.fingerprint)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(dive.fingerprint)
                                                     ? Color.ocean : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dive.start.map {
                                        $0.formatted(date: .abbreviated, time: .shortened)
                                    } ?? "Unknown date")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(subtitle(for: dive))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(dives.count) new dive\(dives.count == 1 ? "" : "s") \(pending.sourceDescription)")
                } footer: {
                    Text("Dives already in your logbook are not shown.")
                }
            }
            .navigationTitle("Import Dives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selection.count == dives.count ? "Deselect All" : "Select All") {
                        selection = selection.count == dives.count
                            ? [] : Set(dives.map(\.fingerprint))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let picked = dives.filter { selection.contains($0.fingerprint) }
                    dismiss()
                    onImport(picked)
                } label: {
                    Text("Import \(selection.count) Dive\(selection.count == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selection.isEmpty)
                .padding()
                .background(.regularMaterial)
            }
        }
    }

    private func subtitle(for dive: Dive) -> String {
        var parts = [dive.activity.label,
                     DiveRow.durationText(dive.duration),
                     String(format: "max %.1f m", dive.maxDepth)]
        if let site = dive.siteName, !site.isEmpty { parts.append(site) }
        return parts.joined(separator: " · ")
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
