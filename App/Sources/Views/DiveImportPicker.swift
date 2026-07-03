import CosmiqKit
import SwiftUI

/// Shown after the sync scan: the dives on the device that aren't in the
/// logbook yet. The user picks which to download.
struct DiveImportPicker: View {
    let candidates: [DiveCandidate]
    let onImport: ([DiveCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String>

    init(candidates: [DiveCandidate], onImport: @escaping ([DiveCandidate]) -> Void) {
        self.candidates = candidates
        self.onImport = onImport
        _selection = State(initialValue: Set(candidates.map(\.id))) // all selected
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        Button {
                            toggle(candidate.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(candidate.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(candidate.id)
                                                     ? Color.ocean : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.summary.start.map {
                                        $0.formatted(date: .abbreviated, time: .shortened)
                                    } ?? "Unknown date")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(candidate.summary.activity.label) · \(DiveRow.durationText(candidate.summary.duration)) · max \(candidate.summary.maxDepth, specifier: "%.1f") m")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(candidates.count) new dive\(candidates.count == 1 ? "" : "s") on the device")
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
                    Button(selection.count == candidates.count ? "Deselect All" : "Select All") {
                        selection = selection.count == candidates.count
                            ? [] : Set(candidates.map(\.id))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let picked = candidates.filter { selection.contains($0.id) }
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

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
