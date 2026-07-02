import CosmiqKit
import SwiftUI

/// Loads the device configuration and pushes edits back, one command at a time.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings = CosmiqSettings()
    @Published var deviceInfo: CosmiqDeviceInfo?
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var clockSynced = false

    private var session: CosmiqSession?

    func attach(ble: CosmiqBLEManager) {
        guard session == nil else { return }
        session = CosmiqSession(ble: ble)
    }

    func loadAll() async {
        guard let session, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            deviceInfo = try await session.readDeviceInfo()
            let result = try await session.readAllSettings()
            settings = result.settings
            // A silent $60 just means an older device without alarms 3-6;
            // only the other queries are worth an error banner.
            let critical = result.failedQueries.filter { $0 != CosmiqCommand.queryFreediveSecondary }
            if critical.isEmpty {
                errorMessage = nil
            } else {
                let names = critical.map { String(format: "$%02X", $0) }
                errorMessage = "Some settings didn't answer (\(names.joined(separator: ", "))). Pull down to retry."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Send a write and refresh the affected values from the device.
    func apply(_ packet: CosmiqPacket) {
        guard let session, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if let verification = try await session.apply(packet) {
                    settings.apply(verification)
                }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setFreediveAlarm(number: Int, meters: Int) {
        let partnerIndex = number.isMultiple(of: 2) ? number - 2 : number
        let partner = settings.freediveDepthAlarms[partnerIndex] ?? 5
        do {
            apply(try CosmiqSettingWrite.freediveDepthAlarm(
                number: number, meters: meters, partnerMeters: partner))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncClock() {
        guard let session, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await session.syncClock()
                clockSynced = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var ble: CosmiqBLEManager
    @StateObject private var model = SettingsModel()

    var body: some View {
        Form {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            deviceSection
            generalSection
            environmentSection
            scubaSection
            freediveSection

            Section {
                Button(role: .destructive) {
                    ble.disconnect()
                } label: {
                    Text("Disconnect")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Unofficial app. Always verify settings on the device screen before diving, and never rely on a single instrument.")
            }
        }
        .disabled(model.isLoading)
        .overlay {
            if model.isLoading {
                ProgressView("Reading settings…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            model.attach(ble: ble)
            await model.loadAll()
        }
        .refreshable {
            await model.loadAll()
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            if let info = model.deviceInfo {
                LabeledContent("Firmware", value: "\(info.firmware)")
                LabeledContent("Serial", value: info.serial)
            }
            Button {
                model.syncClock()
            } label: {
                Label(model.clockSynced ? "Clock Synced ✓" : "Sync Clock to iPhone",
                      systemImage: "clock.arrow.2.circlepath")
            }
            .disabled(model.isBusy)
        }
    }

    private var generalSection: some View {
        Section("General") {
            picker("Default Mode", selection: model.settings.defaultMode, options: DefaultDiveMode.allCases) {
                model.apply(CosmiqSettingWrite.defaultMode($0))
            }
            picker("Units", selection: model.settings.units, options: UnitSystem.allCases) {
                model.apply(CosmiqSettingWrite.units($0))
            }
            picker("Date Display", selection: model.settings.dateDisplay, options: DateDisplayMode.allCases) {
                model.apply(CosmiqSettingWrite.dateDisplay($0))
            }

            Picker("Screen Timeout", selection: Binding(
                get: { model.settings.screenTimeoutSeconds ?? 30 },
                set: { model.apply(CosmiqSettingWrite.screenTimeout(seconds: $0)) }
            )) {
                ForEach(CosmiqSettings.screenTimeoutChoices, id: \.self) { seconds in
                    Text(seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min").tag(seconds)
                }
            }

            Picker("Backlight", selection: Binding(
                get: { model.settings.backlightLevel ?? 3 },
                set: { model.apply(CosmiqSettingWrite.backlightEco(
                    level: $0, eco: model.settings.ecoMode ?? true)) }
            )) {
                ForEach(1...5, id: \.self) { level in
                    Text("Level \(level)").tag(level)
                }
            }

            Toggle("Eco Mode", isOn: Binding(
                get: { model.settings.ecoMode ?? true },
                set: { model.apply(CosmiqSettingWrite.backlightEco(
                    level: model.settings.backlightLevel ?? 3, eco: $0)) }
            ))
        }
    }

    private var environmentSection: some View {
        Section {
            picker("Environment", selection: model.settings.environment, options: EnvironmentMode.allCases) {
                model.apply(CosmiqSettingWrite.environment($0))
            }
        } header: {
            Text("Environment")
        } footer: {
            if model.settings.environment == .highSalinity {
                Text("High salinity mode is for waters like the Red Sea or Dead Sea. Depth readings will differ from standard sea water.")
            }
        }
    }

    private var scubaSection: some View {
        Section("Scuba") {
            picker("Safety Factor", selection: model.settings.safetyFactor, options: SafetyFactor.allCases) {
                model.apply(CosmiqSettingWrite.safetyFactor($0))
            }

            stepperRow(
                title: "Air Mix (O₂)",
                value: model.settings.airMixPercent,
                range: 21...40, unit: "%",
                onCommit: { model.apply(CosmiqSettingWrite.airMix(percent: $0)) }
            )

            Picker("Max PPO₂", selection: Binding(
                get: { model.settings.ppo2 ?? 1.4 },
                set: { model.apply(CosmiqSettingWrite.ppo2(bar: $0)) }
            )) {
                ForEach([1.2, 1.3, 1.4, 1.5, 1.6], id: \.self) { value in
                    Text(String(format: "%.1f bar", value)).tag(value)
                }
            }

            stepperRow(
                title: "Depth Alarm",
                value: model.settings.scubaDepthAlarmMeters.map { Int($0) },
                range: 5...60, unit: "m",
                onCommit: { model.apply(CosmiqSettingWrite.scubaDepthAlarm(meters: $0)) }
            )

            stepperRow(
                title: "Time Alarm",
                value: model.settings.scubaTimeAlarmMinutes,
                range: 1...99, unit: "min",
                onCommit: { model.apply(CosmiqSettingWrite.scubaTimeAlarm(minutes: $0)) }
            )
        }
    }

    private var freediveSection: some View {
        Section {
            stepperRow(
                title: "Max Time",
                value: model.settings.freediveMaxTimeSeconds,
                range: 30...600, step: 5, unit: "s",
                onCommit: { model.apply(CosmiqSettingWrite.freediveMaxTime(seconds: $0)) }
            )

            ForEach(1...(hasExtendedAlarms ? 6 : 2), id: \.self) { number in
                stepperRow(
                    title: "Depth Alarm \(number)",
                    value: model.settings.freediveDepthAlarms[number - 1],
                    range: 5...120, unit: "m",
                    onCommit: { model.setFreediveAlarm(number: number, meters: $0) }
                )
            }
        } header: {
            Text("Freedive")
        } footer: {
            if !hasExtendedAlarms {
                Text("Depth alarms 3–6 exist only on the Cosmiq Gen 5; this device reports alarms 1–2.")
            }
        }
    }

    /// True when the device answered the $60 query (Gen 5 firmware).
    private var hasExtendedAlarms: Bool {
        model.settings.freediveDepthAlarms[2] != nil
    }

    // MARK: Row helpers

    private func picker<Option: Identifiable & Hashable & LabeledOption>(
        _ title: String, selection: Option?, options: [Option],
        onChange: @escaping (Option) -> Void
    ) -> some View {
        Picker(title, selection: Binding(
            get: { selection ?? options[0] },
            set: { onChange($0) }
        )) {
            ForEach(options) { option in
                Text(option.label).tag(option)
            }
        }
        .disabled(selection == nil)
    }

    private func stepperRow(
        title: String, value: Int?, range: ClosedRange<Int>, step: Int = 1,
        unit: String, onCommit: @escaping (Int) -> Void
    ) -> some View {
        Stepper(value: Binding(
            get: { value ?? range.lowerBound },
            set: { onCommit($0) }
        ), in: range, step: step) {
            LabeledContent(title, value: value.map { "\($0) \(unit)" } ?? "—")
        }
        .disabled(value == nil)
    }
}

/// Settings enums that carry a display label.
protocol LabeledOption {
    var label: String { get }
}

extension DefaultDiveMode: LabeledOption {}
extension UnitSystem: LabeledOption {}
extension DateDisplayMode: LabeledOption {}
extension EnvironmentMode: LabeledOption {}
extension SafetyFactor: LabeledOption {}
