import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager

    var body: some View {
        TabView {
            NavigationStack {
                DeviceView()
            }
            .tabItem { Label("Device", systemImage: "gauge.with.dots.needle.50percent") }

            NavigationStack {
                LogbookView()
            }
            .tabItem { Label("Logbook", systemImage: "book.closed") }

            NavigationStack {
                DiagnosticsView()
            }
            .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
    }
}

/// Root of the Device tab: connect screen or settings, depending on state.
struct DeviceView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager

    var body: some View {
        Group {
            if ble.state.isConnected {
                SettingsView()
            } else {
                ConnectView()
            }
        }
        .navigationTitle(ble.state.isConnected ? (ble.deviceName ?? "COSMIQ+") : "Connect")
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager

    var body: some View {
        List(Array(ble.packetLog.enumerated()), id: \.offset) { _, entry in
            Text(entry)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.hasPrefix("TX") ? .blue : .primary)
        }
        .navigationTitle("Packet Log")
        .overlay {
            if ble.packetLog.isEmpty {
                ContentUnavailableView("No traffic yet",
                                       systemImage: "waveform.path.ecg",
                                       description: Text("Raw packets appear here once you talk to the device."))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CosmiqBLEManager())
        .environmentObject(Logbook())
}
