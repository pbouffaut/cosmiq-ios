import XCTest
@testable import CosmiqKit

final class SettingsTests: XCTestCase {
    func testParseSystemPacket() {
        var settings = CosmiqSettings()
        // $5F payload: [?, env, backlight/eco mask, ...]
        // mask 0x15 = eco disabled (bit 4) + nibble 5 -> level 3
        settings.apply(CosmiqPacket(command: 0x5F, payload: [0x00, 0x01, 0x15]))
        XCTAssertEqual(settings.environment, .highSalinity)
        XCTAssertEqual(settings.backlightLevel, 3)
        XCTAssertEqual(settings.ecoMode, false)

        // mask 0x07 = eco on, nibble 7 -> level 5
        settings.apply(CosmiqPacket(command: 0x5F, payload: [0x00, 0x02, 0x07]))
        XCTAssertEqual(settings.environment, .highAltitude)
        XCTAssertEqual(settings.backlightLevel, 5)
        XCTAssertEqual(settings.ecoMode, true)
    }

    func testParseScubaPrimaryPacket() {
        var settings = CosmiqSettings()
        // depth raw 0x0FA0 = 4000 -> (4000-1000)/100 = 30 m; time 0x0014 = 20 min;
        // air 0x20 = 32%; mode 0 = scuba
        settings.apply(CosmiqPacket(command: 0x5C, payload: [0x0F, 0xA0, 0x00, 0x14, 0x20, 0x00]))
        XCTAssertEqual(settings.scubaDepthAlarmMeters, 30)
        XCTAssertEqual(settings.scubaTimeAlarmMinutes, 20)
        XCTAssertEqual(settings.airMixPercent, 32)
        XCTAssertEqual(settings.defaultMode, .scuba)
    }

    func testParseScubaSecondaryPacket() {
        var settings = CosmiqSettings()
        // timeout devVal 2 -> 60 s; date mode 1; units 1 = metric
        settings.apply(CosmiqPacket(command: 0x5B, payload: [0x00, 0x00, 0x00, 0x02, 0x01, 0x01]))
        XCTAssertEqual(settings.screenTimeoutSeconds, 60)
        XCTAssertEqual(settings.dateDisplay, .lastDive)
        XCTAssertEqual(settings.units, .metric)

        // Raw-seconds timeouts pass through the map too (10 -> 10 s).
        settings.apply(CosmiqPacket(command: 0x5B, payload: [0x00, 0x00, 0x00, 0x0A, 0x00, 0x00]))
        XCTAssertEqual(settings.screenTimeoutSeconds, 10)
        XCTAssertEqual(settings.units, .imperial)
    }

    func testParseFreedivePackets() {
        var settings = CosmiqSettings()
        // $5D: [fd2-5, fd1-5, ?, timeIdx, safety, ppo2*10]
        // fd2 = 0x0F+5 = 20 m, fd1 = 0x05+5 = 10 m, time = 6*5+30 = 60 s,
        // safety = progressive, ppo2 = 1.4
        settings.apply(CosmiqPacket(command: 0x5D, payload: [0x0F, 0x05, 0x00, 0x06, 0x02, 0x0E]))
        XCTAssertEqual(settings.freediveDepthAlarms[0], 10)
        XCTAssertEqual(settings.freediveDepthAlarms[1], 20)
        XCTAssertEqual(settings.freediveMaxTimeSeconds, 60)
        XCTAssertEqual(settings.safetyFactor, .progressive)
        XCTAssertEqual(settings.ppo2, 1.4)

        // $60: [fd4, fd3, fd6, fd5] (all -5)
        settings.apply(CosmiqPacket(command: 0x60, payload: [0x19, 0x14, 0x23, 0x1E]))
        XCTAssertEqual(settings.freediveDepthAlarms[2], 25) // fd3 = 0x14+5
        XCTAssertEqual(settings.freediveDepthAlarms[3], 30) // fd4 = 0x19+5
        XCTAssertEqual(settings.freediveDepthAlarms[4], 35) // fd5 = 0x1E+5
        XCTAssertEqual(settings.freediveDepthAlarms[5], 40) // fd6 = 0x23+5
    }

    func testFreediveAlarmWritePairing() throws {
        // Setting alarm 1 to 15 m with partner (alarm 2) at 20 m:
        // payload must be [even][odd] = [20-5, 15-5]
        let alarm1 = try CosmiqSettingWrite.freediveDepthAlarm(number: 1, meters: 15, partnerMeters: 20)
        XCTAssertEqual(alarm1.command, 0x25)
        XCTAssertEqual(alarm1.payload, [0x0F, 0x0A])

        // Setting alarm 4 to 30 m with partner (alarm 3) at 25 m: [30-5, 25-5]
        let alarm4 = try CosmiqSettingWrite.freediveDepthAlarm(number: 4, meters: 30, partnerMeters: 25)
        XCTAssertEqual(alarm4.command, 0x31)
        XCTAssertEqual(alarm4.payload, [0x19, 0x14])

        // Alarm 5 (odd) pairs with 6: [partner, own]
        let alarm5 = try CosmiqSettingWrite.freediveDepthAlarm(number: 5, meters: 35, partnerMeters: 40)
        XCTAssertEqual(alarm5.command, 0x32)
        XCTAssertEqual(alarm5.payload, [0x23, 0x1E])
    }

    func testWriteEncodings() {
        XCTAssertEqual(CosmiqSettingWrite.environment(.highAltitude).payload, [0x00, 0x02])
        XCTAssertEqual(CosmiqSettingWrite.backlightEco(level: 3, eco: false).payload, [0x15])
        XCTAssertEqual(CosmiqSettingWrite.backlightEco(level: 5, eco: true).payload, [0x07])
        XCTAssertEqual(CosmiqSettingWrite.screenTimeout(seconds: 30).payload, [0x00, 0x01])
        XCTAssertEqual(CosmiqSettingWrite.screenTimeout(seconds: 15).payload, [0x00, 0x0F])
        XCTAssertEqual(CosmiqSettingWrite.scubaDepthAlarm(meters: 30).payload, [0x0F, 0xA0])
        XCTAssertEqual(CosmiqSettingWrite.scubaTimeAlarm(minutes: 45).payload, [0x00, 0x2D])
        XCTAssertEqual(CosmiqSettingWrite.freediveMaxTime(seconds: 60).payload, [0x14, 0x06])
        XCTAssertEqual(CosmiqSettingWrite.airMix(percent: 32).payload, [0x20])
        XCTAssertEqual(CosmiqSettingWrite.ppo2(bar: 1.4).payload, [0x0E])
        XCTAssertEqual(CosmiqSettingWrite.safetyFactor(.normal).payload, [0x00, 0x01])
    }

    func testRoundTripWriteThenParse() {
        // A written backlight/eco packet parsed back through $5F must yield the
        // same level/eco values.
        let write = CosmiqSettingWrite.backlightEco(level: 2, eco: false)
        var settings = CosmiqSettings()
        settings.apply(CosmiqPacket(command: 0x5F, payload: [0x00, 0x00, write.payload[0]]))
        XCTAssertEqual(settings.backlightLevel, 2)
        XCTAssertEqual(settings.ecoMode, false)
    }

    func testVerificationQueryMapping() {
        XCTAssertEqual(CosmiqSettingWrite.verificationQuery(for: CosmiqCommand.setAirMix),
                       CosmiqCommand.queryScubaPrimary)
        XCTAssertEqual(CosmiqSettingWrite.verificationQuery(for: CosmiqCommand.setBacklightEco),
                       CosmiqCommand.querySystem)
        XCTAssertNil(CosmiqSettingWrite.verificationQuery(for: CosmiqCommand.setDateTime))
    }
}
