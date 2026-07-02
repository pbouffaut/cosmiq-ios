import CoreLocation
import CosmiqKit
import MapKit
import SwiftUI

/// Sheet for editing the user metadata of a dive.
struct DiveEditView: View {
    @EnvironmentObject private var logbook: Logbook
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = LocationProvider()

    @State var dive: Dive
    @State private var showMapPicker = false
    @State private var fetchingLocation = false
    @State private var locationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dive") {
                    TextField("Name (e.g. Night dive with turtles)", text: optional($dive.name))
                    TextField("Dive site", text: optional($dive.siteName))
                }

                Section {
                    DatePicker(
                        "Date & Time",
                        selection: Binding(
                            get: { dive.userDate ?? dive.start ?? Date() },
                            set: { dive.userDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    if dive.userDate != nil {
                        Button("Reset to dive computer time") {
                            dive.userDate = nil
                        }
                        .disabled(dive.start == nil)
                    }
                } header: {
                    Text("Date & Time")
                } footer: {
                    if let start = dive.start, dive.userDate != nil {
                        Text("Computer recorded: \(start.formatted(date: .abbreviated, time: .shortened))")
                    }
                }

                Section("Location") {
                    if let coordinate = dive.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                           longitude: coordinate.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))) {
                            Marker(dive.siteName ?? "Dive site",
                                   systemImage: "water.waves",
                                   coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                      longitude: coordinate.longitude))
                        }
                        .frame(height: 160)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }

                    Button {
                        useCurrentLocation()
                    } label: {
                        if fetchingLocation {
                            HStack { ProgressView(); Text("Locating…").padding(.leading, 6) }
                        } else {
                            Label("Use Current Location", systemImage: "location.fill")
                        }
                    }
                    .disabled(fetchingLocation)

                    Button {
                        showMapPicker = true
                    } label: {
                        Label("Pick on Map", systemImage: "mappin.and.ellipse")
                    }

                    if dive.coordinate != nil {
                        Button(role: .destructive) {
                            dive.latitude = nil
                            dive.longitude = nil
                        } label: {
                            Label("Remove Location", systemImage: "mappin.slash")
                        }
                    }

                    if let locationError {
                        Text(locationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Notes") {
                    TextEditor(text: optional($dive.notes))
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Dive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        logbook.update(dive)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showMapPicker) {
                MapPickerView(latitude: $dive.latitude, longitude: $dive.longitude)
            }
        }
    }

    private func useCurrentLocation() {
        fetchingLocation = true
        locationError = nil
        Task {
            defer { fetchingLocation = false }
            do {
                let coordinate = try await locationProvider.currentLocation()
                dive.latitude = coordinate.latitude
                dive.longitude = coordinate.longitude
            } catch {
                locationError = error.localizedDescription
            }
        }
    }

    /// TextField/TextEditor binding for optional strings: empty text = nil.
    private func optional(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

/// Full-screen map: tap to drop the dive-site flag.
struct MapPickerView: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @Environment(\.dismiss) private var dismiss

    @State private var selected: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(initialPosition: initialPosition) {
                    if let selected {
                        Marker("Dive site", systemImage: "flag.fill", coordinate: selected)
                            .tint(.orange)
                    }
                    UserAnnotation()
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .onTapGesture { screenPoint in
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        selected = coordinate
                    }
                }
            }
            .navigationTitle("Tap to place the flag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set Location") {
                        if let selected {
                            latitude = selected.latitude
                            longitude = selected.longitude
                        }
                        dismiss()
                    }
                    .disabled(selected == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let latitude, let longitude {
                    selected = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                }
            }
        }
    }

    private var initialPosition: MapCameraPosition {
        if let latitude, let longitude {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
        }
        return .userLocation(fallback: .automatic)
    }
}
