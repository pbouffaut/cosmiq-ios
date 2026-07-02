import Foundation

/// COSMIQ+ command bytes.
///
/// Settings commands come from cosmiq5-web's reverse engineering
/// (technical_documentation.md); dive-log and system commands from
/// libdivecomputer's deepblu_cosmiq.c.
public enum CosmiqCommand {
    // MARK: Settings writes
    public static let setDateTime: UInt8 = 0x20
    public static let setSafetyFactor: UInt8 = 0x21
    public static let setAirMix: UInt8 = 0x22
    public static let setUnits: UInt8 = 0x23
    public static let setDateFormat: UInt8 = 0x24
    public static let setFreediveAlarms12: UInt8 = 0x25
    public static let setFreediveMaxTime: UInt8 = 0x26
    public static let setScubaDepthAlarm: UInt8 = 0x27
    public static let setScubaTimeAlarm: UInt8 = 0x28
    public static let setScreenTimeout: UInt8 = 0x2A
    public static let setDefaultMode: UInt8 = 0x2B
    public static let setPPO2: UInt8 = 0x2D
    public static let setBacklightEco: UInt8 = 0x2E
    public static let setEnvironment: UInt8 = 0x30
    public static let setFreediveAlarms34: UInt8 = 0x31
    public static let setFreediveAlarms56: UInt8 = 0x32

    // MARK: Dive log
    public static let diveCount: UInt8 = 0x40
    public static let diveHeader: UInt8 = 0x41
    public static let diveHeaderData: UInt8 = 0x42
    public static let diveProfile: UInt8 = 0x43
    public static let diveProfileData: UInt8 = 0x44

    // MARK: System / configuration queries
    public static let queryFirmware: UInt8 = 0x58
    public static let queryMacAddress: UInt8 = 0x5A
    public static let queryScubaSecondary: UInt8 = 0x5B  // timeout, date format, units
    public static let queryScubaPrimary: UInt8 = 0x5C    // alarms, air mix, default mode
    public static let queryFreedivePrimary: UInt8 = 0x5D // FD alarms 1-2, FD time, safety, PPO2
    public static let querySystem: UInt8 = 0x5F          // environment, backlight, eco
    public static let queryFreediveSecondary: UInt8 = 0x60 // FD alarms 3-6

    /// Reply command byte the device uses to signal a rejected command.
    public static let rejected: UInt8 = 0x80

    /// The queries needed to populate a full `CosmiqSettings`.
    public static let settingsQueries: [UInt8] = [
        querySystem, queryScubaSecondary, queryScubaPrimary,
        queryFreedivePrimary, queryFreediveSecondary,
    ]

    /// Simple query packet (`payload = 00`), used for all read commands.
    public static func query(_ command: UInt8) -> CosmiqPacket {
        CosmiqPacket(command: command, payload: [0x00])
    }
}
