import Foundation

public enum EnvironmentMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case normal = 0
    case highSalinity = 1
    case highAltitude = 2

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .highSalinity: return "High Salinity"
        case .highAltitude: return "High Altitude"
        }
    }
}

public enum SafetyFactor: Int, CaseIterable, Codable, Sendable, Identifiable {
    case conservative = 0
    case normal = 1
    case progressive = 2

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .conservative: return "Conservative"
        case .normal: return "Normal"
        case .progressive: return "Progressive"
        }
    }
}

public enum UnitSystem: Int, CaseIterable, Codable, Sendable, Identifiable {
    case imperial = 0
    case metric = 1

    public var id: Int { rawValue }
    public var label: String { self == .metric ? "Metric" : "Imperial" }
}

public enum DateDisplayMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case currentDate = 0
    case lastDive = 1

    public var id: Int { rawValue }
    public var label: String { self == .currentDate ? "Current Date" : "Last Dive" }
}

public enum DefaultDiveMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case scuba = 0
    case gauge = 1
    case freedive = 2

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .scuba: return "Scuba"
        case .gauge: return "Gauge"
        case .freedive: return "Freedive"
        }
    }
}

/// Snapshot of the device configuration, populated from the `$5F/$5C/$5B/$5D/$60`
/// query replies. Fields stay nil until the matching packet has been parsed.
public struct CosmiqSettings: Equatable, Sendable {
    /// Screen timeout choices the device supports, in seconds.
    public static let screenTimeoutChoices = [5, 10, 15, 20, 30, 60, 120]
    /// Wire encoding of the screen timeout (seconds -> device value).
    static let screenTimeoutToDevice: [Int: UInt8] = [
        5: 5, 10: 10, 15: 15, 20: 20, 30: 1, 60: 2, 120: 3,
    ]

    public var environment: EnvironmentMode?
    /// Backlight level 1...5 (wire nibble is level + 2).
    public var backlightLevel: Int?
    public var ecoMode: Bool?
    public var screenTimeoutSeconds: Int?
    public var units: UnitSystem?
    public var dateDisplay: DateDisplayMode?
    public var defaultMode: DefaultDiveMode?
    /// Nitrox oxygen fraction in percent (21...40).
    public var airMixPercent: Int?
    /// Max PPO2 in bar (1.2...1.6).
    public var ppo2: Double?
    public var safetyFactor: SafetyFactor?
    public var scubaDepthAlarmMeters: Double?
    public var scubaTimeAlarmMinutes: Int?
    /// Freedive max time alarm, 30...600 s.
    public var freediveMaxTimeSeconds: Int?
    /// Freedive depth alarms 1...6 in meters, index 0 = alarm 1.
    public var freediveDepthAlarms: [Int?] = Array(repeating: nil, count: 6)

    public init() {}

    public var isComplete: Bool {
        environment != nil && backlightLevel != nil && screenTimeoutSeconds != nil
            && units != nil && defaultMode != nil && airMixPercent != nil
            && safetyFactor != nil && freediveDepthAlarms.allSatisfy { $0 != nil }
    }

    /// Fold a query reply into the snapshot. Unknown commands are ignored.
    public mutating func apply(_ packet: CosmiqPacket) {
        let p = packet.payload
        switch packet.command {
        case CosmiqCommand.querySystem: // $5F
            guard p.count >= 3 else { return }
            environment = EnvironmentMode(rawValue: Int(p[1]))
            let mask = p[2]
            backlightLevel = max(1, min(5, Int(mask & 0x0F) - 2))
            ecoMode = (mask & 0x10) == 0

        case CosmiqCommand.queryScubaPrimary: // $5C
            guard p.count >= 6 else { return }
            let depthRaw = Int(p[0]) << 8 | Int(p[1])
            scubaDepthAlarmMeters = Double(depthRaw - 1000) / 100.0
            scubaTimeAlarmMinutes = Int(p[2]) << 8 | Int(p[3])
            airMixPercent = Int(p[4])
            defaultMode = DefaultDiveMode(rawValue: Int(p[5]))

        case CosmiqCommand.queryScubaSecondary: // $5B
            guard p.count >= 6 else { return }
            screenTimeoutSeconds = Self.screenTimeoutToDevice.first { $0.value == p[3] }?.key
            dateDisplay = DateDisplayMode(rawValue: Int(p[4]))
            units = UnitSystem(rawValue: Int(p[5]))

        case CosmiqCommand.queryFreedivePrimary: // $5D
            guard p.count >= 6 else { return }
            freediveDepthAlarms[1] = Int(p[0]) + 5
            freediveDepthAlarms[0] = Int(p[1]) + 5
            freediveMaxTimeSeconds = Int(p[3]) * 5 + 30
            safetyFactor = SafetyFactor(rawValue: Int(p[4]))
            ppo2 = Double(p[5]) / 10.0

        case CosmiqCommand.queryFreediveSecondary: // $60
            guard p.count >= 4 else { return }
            freediveDepthAlarms[3] = Int(p[0]) + 5
            freediveDepthAlarms[2] = Int(p[1]) + 5
            freediveDepthAlarms[5] = Int(p[2]) + 5
            freediveDepthAlarms[4] = Int(p[3]) + 5

        default:
            break
        }
    }
}

/// Builders for the settings write packets.
public enum CosmiqSettingWrite {
    /// Set the device clock. Bytes are BCD-encoded YY MM DD HH MM SS.
    public static func systemTime(_ date: Date, calendar: Calendar = .current) -> CosmiqPacket {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func bcd(_ value: Int) -> UInt8 { UInt8((value / 10) << 4 | (value % 10)) }
        return CosmiqPacket(command: CosmiqCommand.setDateTime, payload: [
            bcd((c.year ?? 2000) % 100), bcd(c.month ?? 1), bcd(c.day ?? 1),
            bcd(c.hour ?? 0), bcd(c.minute ?? 0), bcd(c.second ?? 0),
        ])
    }

    public static func environment(_ mode: EnvironmentMode) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setEnvironment, payload: [0x00, UInt8(mode.rawValue)])
    }

    /// - Parameter level: 1...5, shown on the device as brightness steps.
    public static func backlightEco(level: Int, eco: Bool) -> CosmiqPacket {
        let nibble = UInt8(max(1, min(5, level)) + 2)
        let mask = nibble | (eco ? 0x00 : 0x10)
        return CosmiqPacket(command: CosmiqCommand.setBacklightEco, payload: [mask])
    }

    /// - Parameter seconds: one of `CosmiqSettings.screenTimeoutChoices`.
    public static func screenTimeout(seconds: Int) -> CosmiqPacket {
        let device = CosmiqSettings.screenTimeoutToDevice[seconds] ?? 1
        return CosmiqPacket(command: CosmiqCommand.setScreenTimeout, payload: [0x00, device])
    }

    public static func units(_ units: UnitSystem) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setUnits, payload: [UInt8(units.rawValue)])
    }

    public static func dateDisplay(_ mode: DateDisplayMode) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setDateFormat, payload: [UInt8(mode.rawValue)])
    }

    public static func defaultMode(_ mode: DefaultDiveMode) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setDefaultMode, payload: [UInt8(mode.rawValue)])
    }

    public static func safetyFactor(_ factor: SafetyFactor) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setSafetyFactor, payload: [0x00, UInt8(factor.rawValue)])
    }

    /// - Parameter percent: oxygen fraction, 21...40.
    public static func airMix(percent: Int) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setAirMix, payload: [UInt8(max(21, min(40, percent)))])
    }

    /// - Parameter bar: 1.2...1.6.
    public static func ppo2(bar: Double) -> CosmiqPacket {
        let raw = UInt8((max(1.2, min(1.6, bar)) * 10).rounded())
        return CosmiqPacket(command: CosmiqCommand.setPPO2, payload: [raw])
    }

    public static func scubaDepthAlarm(meters: Int) -> CosmiqPacket {
        let raw = meters * 100 + 1000
        return CosmiqPacket(command: CosmiqCommand.setScubaDepthAlarm,
                            payload: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
    }

    public static func scubaTimeAlarm(minutes: Int) -> CosmiqPacket {
        CosmiqPacket(command: CosmiqCommand.setScubaTimeAlarm,
                     payload: [UInt8(minutes >> 8), UInt8(minutes & 0xFF)])
    }

    /// - Parameter seconds: 30...600, in 5 s steps.
    public static func freediveMaxTime(seconds: Int) -> CosmiqPacket {
        let clamped = max(30, min(600, seconds))
        return CosmiqPacket(command: CosmiqCommand.setFreediveMaxTime,
                            payload: [0x14, UInt8((clamped - 30) / 5)])
    }

    /// Freedive depth alarms live in pairs (1-2, 3-4, 5-6) and must be written
    /// together, even-numbered alarm first. `partnerMeters` is the current value
    /// of the paired alarm, which the caller reads from `CosmiqSettings`.
    public static func freediveDepthAlarm(number: Int, meters: Int, partnerMeters: Int) throws -> CosmiqPacket {
        guard (1...6).contains(number) else {
            throw CosmiqProtocolError.malformedPacket("freedive alarm \(number)")
        }
        let command: UInt8
        switch number {
        case 1, 2: command = CosmiqCommand.setFreediveAlarms12
        case 3, 4: command = CosmiqCommand.setFreediveAlarms34
        default: command = CosmiqCommand.setFreediveAlarms56
        }
        let own = UInt8(max(0, meters - 5))
        let partner = UInt8(max(0, partnerMeters - 5))
        // Payload order is [even alarm][odd alarm].
        let payload = number.isMultiple(of: 2) ? [own, partner] : [partner, own]
        return CosmiqPacket(command: command, payload: payload)
    }

    /// The query command that reads back the value a write affects, used to
    /// verify after writing (the device echoes stale values otherwise).
    public static func verificationQuery(for command: UInt8) -> UInt8? {
        switch command {
        case CosmiqCommand.setEnvironment, CosmiqCommand.setBacklightEco:
            return CosmiqCommand.querySystem
        case CosmiqCommand.setAirMix, CosmiqCommand.setScubaDepthAlarm,
             CosmiqCommand.setScubaTimeAlarm, CosmiqCommand.setDefaultMode:
            return CosmiqCommand.queryScubaPrimary
        case CosmiqCommand.setUnits, CosmiqCommand.setDateFormat, CosmiqCommand.setScreenTimeout:
            return CosmiqCommand.queryScubaSecondary
        case CosmiqCommand.setSafetyFactor, CosmiqCommand.setPPO2,
             CosmiqCommand.setFreediveMaxTime, CosmiqCommand.setFreediveAlarms12:
            return CosmiqCommand.queryFreedivePrimary
        case CosmiqCommand.setFreediveAlarms34, CosmiqCommand.setFreediveAlarms56:
            return CosmiqCommand.queryFreediveSecondary
        default:
            return nil
        }
    }
}
