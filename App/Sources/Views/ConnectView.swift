import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager

    var body: some View {
        List {
            Section {
                SeaBanner(animateIcon: ble.state == .scanning)
            }

            Section {
                switch ble.state {
                case .bluetoothOff:
                    Label("Bluetooth is off or not authorized", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                case .connecting:
                    HStack {
                        ProgressView()
                        Text("Connecting…").padding(.leading, 8)
                    }
                default:
                    EmptyView()
                }

                if ble.state == .scanning || !ble.discovered.isEmpty {
                    ForEach(ble.discovered) { device in
                        Button {
                            ble.connect(device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.displayName).font(.headline)
                                    Text("Signal: \(device.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if ble.state == .scanning {
                        HStack {
                            ProgressView()
                            Text("Scanning… wake up your COSMIQ+")
                                .padding(.leading, 8)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Turn the dive computer on and keep it close to your iPhone. It usually advertises as “COSMIQ” or “Deepblu”; a Gen 5 may briefly appear as “Unnamed dive computer” until its name comes in. If nothing shows up, the Diagnostics tab lists every device the scan saw.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                ble.state == .scanning ? ble.stopScan() : ble.startScan()
            } label: {
                Text(ble.state == .scanning ? "Stop Scanning" : "Scan for COSMIQ+")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .disabled(ble.state == .bluetoothOff || ble.state == .connecting)
        }
    }
}
