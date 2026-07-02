import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient.opacity(0.25))
                            .frame(width: 92, height: 92)
                        Image(systemName: "water.waves")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Color.foam)
                            .symbolEffect(.variableColor.iterative,
                                          isActive: ble.state == .scanning)
                    }
                    Text("COSMIQ+")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Your dive computer, alive and well.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.seaGradient, in: RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
                                    Text(device.name).font(.headline)
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
                Text("Turn the dive computer on and keep it close to your iPhone. It advertises as “COSMIQ” or “Deepblu”.")
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
