import XCTest
@testable import CosmiqKit

final class DiveTests: XCTestCase {
    /// Build a synthetic 36-byte header per the layout in libdivecomputer's
    /// deepblu_cosmiq_parser.c.
    private func makeHeader(
        activity: DiveActivity = .scuba,
        oxygen: UInt8 = 32,
        atmospheric: Int = 1013,
        year: Int = 2026, month: UInt8 = 6, day: UInt8 = 15,
        hour: UInt8 = 14, minute: UInt8 = 30,
        duration: Int = 45,
        maxPressureMillibar: Int = 3013,
        interval: UInt8 = 20
    ) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: DiveParser.headerSize)
        header[2] = UInt8(activity.rawValue)
        header[3] = oxygen
        header[4] = UInt8(atmospheric & 0xFF)
        header[5] = UInt8(atmospheric >> 8)
        header[6] = UInt8(year & 0xFF)
        header[7] = UInt8(year >> 8)
        header[8] = day
        header[9] = month
        header[10] = minute
        header[11] = hour
        header[12] = UInt8(duration & 0xFF)
        header[13] = UInt8(duration >> 8)
        header[22] = UInt8(maxPressureMillibar & 0xFF)
        header[23] = UInt8(maxPressureMillibar >> 8)
        header[26] = interval
        return header
    }

    private func makeSample(temperatureDeciC: Int, pressureMillibar: Int) -> [UInt8] {
        [UInt8(temperatureDeciC & 0xFF), UInt8(temperatureDeciC >> 8),
         UInt8(pressureMillibar & 0xFF), UInt8(pressureMillibar >> 8)]
    }

    func testParseScubaDive() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513) // 5 m, 28.5 C
        data += makeSample(temperatureDeciC: 280, pressureMillibar: 3013) // 20 m
        data += [0xFF, 0xFF, 0xFF, 0xFF] // erased slot must be skipped
        data += makeSample(temperatureDeciC: 282, pressureMillibar: 2013) // 10 m

        let dive = try DiveParser.parse(data: Data(data))

        XCTAssertEqual(dive.activity, .scuba)
        XCTAssertEqual(dive.oxygenPercent, 32)
        XCTAssertEqual(dive.atmosphericMillibar, 1013)
        XCTAssertEqual(dive.duration, 45 * 60, "scuba dive time is stored in minutes")
        XCTAssertEqual(dive.sampleIntervalSeconds, 20)
        XCTAssertEqual(dive.samples.count, 3)

        // Fresh water (salt flag unset): depth = (p - surface) / 100
        XCTAssertEqual(dive.maxDepth, 20.0, accuracy: 0.01)

        XCTAssertEqual(dive.samples[0].time, 20)
        XCTAssertEqual(dive.samples[0].temperature, 28.5, accuracy: 0.001)
        XCTAssertEqual(dive.samples[0].depth, 5.0, accuracy: 0.01)
        // Sample times are positional, so an erased slot still advances time.
        XCTAssertEqual(dive.samples[2].time, 80)

        // Date comes from the odd header layout (minute before hour).
        let calendar = Calendar.current
        let start = try XCTUnwrap(dive.start)
        XCTAssertEqual(calendar.component(.year, from: start), 2026)
        XCTAssertEqual(calendar.component(.month, from: start), 6)
        XCTAssertEqual(calendar.component(.day, from: start), 15)
        XCTAssertEqual(calendar.component(.hour, from: start), 14)
        XCTAssertEqual(calendar.component(.minute, from: start), 30)
    }

    func testFreediveDurationIsSecondsAndIntervalIsOneSecond() throws {
        var data = makeHeader(activity: .freedive, duration: 95)
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        let dive = try DiveParser.parse(data: Data(data))
        XCTAssertEqual(dive.duration, 95)
        XCTAssertEqual(dive.sampleIntervalSeconds, 1, "the app hard-codes 1 s for freedives")
        XCTAssertEqual(dive.samples[0].time, 1)
    }

    func testSaltFlagAndPressureSentinel() throws {
        // Salt flag set (reserved bit 0) -> depth divisor 102.5.
        var salty = makeHeader()
        salty[20] = 0x01
        salty += makeSample(temperatureDeciC: 285, pressureMillibar: 3063)
        let saltDive = try DiveParser.parse(data: Data(salty))
        XCTAssertEqual(saltDive.samples[0].depth, 20.0, accuracy: 0.01)

        // dvsetting 0x80B4 means standard 1000 mbar surface pressure.
        var sentinel = makeHeader()
        sentinel[4] = 0xB4
        sentinel[5] = 0x80
        let sentinelDive = try DiveParser.parse(data: Data(sentinel))
        XCTAssertEqual(sentinelDive.atmosphericMillibar, 1000)
    }

    func testSamplesPastDiveTimeAreCut() throws {
        // 1-minute dive at 20 s interval: only 3 sample slots belong to it.
        var data = makeHeader(duration: 1)
        for _ in 0..<6 {
            data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        }
        let dive = try DiveParser.parse(data: Data(data))
        XCTAssertEqual(dive.samples.count, 3)
    }

    func testProfileSlotMapping() {
        func header(sector: Int, samples: Int = 10) -> [UInt8] {
            var h = [UInt8](repeating: 0, count: DiveParser.headerSize)
            h[30] = UInt8(sector & 0xFF); h[31] = UInt8(sector >> 8)
            h[28] = UInt8(samples & 0xFF); h[29] = UInt8(samples >> 8)
            return h
        }
        // Dive 0 at sector 300 overwrote dive 2 at sector 44; dive 1 at
        // sector 260 has no matching older dive; dive 3 at sector 50 is intact.
        let headers = [header(sector: 300), header(sector: 260),
                       header(sector: 44), header(sector: 50)]
        XCTAssertEqual(DiveParser.profileSlot(forDiveAt: 0, headers: headers), .recovered(2))
        XCTAssertEqual(DiveParser.profileSlot(forDiveAt: 1, headers: headers), .unreachable)
        XCTAssertEqual(DiveParser.profileSlot(forDiveAt: 2, headers: headers), .overwritten)
        XCTAssertEqual(DiveParser.profileSlot(forDiveAt: 3, headers: headers), .own(3))
        XCTAssertEqual(DiveParser.sampleCount(ofHeader: headers[0]), 10)
        XCTAssertEqual(DiveParser.startSector(ofHeader: headers[0]), 300)
    }

    func testStripErased() {
        let body: [UInt8] = [1, 2, 3, 4, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        XCTAssertEqual(DiveParser.stripErased(body), [1, 2, 3, 4])
        XCTAssertEqual(DiveParser.stripErased([0xFF, 0xFF, 0xFF, 0xFF]), [])
    }

    func testFingerprintMatchesTimestampBytes() throws {
        let header = makeHeader()
        let dive = try DiveParser.parse(data: Data(header))
        XCTAssertEqual(dive.fingerprint, header[6..<12].hexString)
        XCTAssertEqual(DiveParser.fingerprint(ofHeader: header), dive.fingerprint)
    }

    func testTooShortRecordThrows() {
        XCTAssertThrowsError(try DiveParser.parse(data: Data([0x01, 0x02])))
    }

    func testCSVExport() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        let dive = try DiveParser.parse(data: Data(data))
        let csv = DiveExporter.csv(for: dive)
        XCTAssertTrue(csv.hasPrefix("time_s,depth_m,temperature_c\n"))
        XCTAssertTrue(csv.contains("20,5.00,28.50"))
    }

    func testUDDFExport() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        let dive = try DiveParser.parse(data: Data(data))
        let uddf = DiveExporter.uddf(for: [dive])
        XCTAssertTrue(uddf.contains("<uddf"))
        XCTAssertTrue(uddf.contains("<mix id=\"mix32\">"))
        XCTAssertTrue(uddf.contains("<divetime>20</divetime>"))
        // 28.5 C in Kelvin
        XCTAssertTrue(uddf.contains("<temperature>301.65</temperature>"))
    }

    func testTrimmedSamplesCutsSurfaceTail() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 2013) // ~10 m
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 3013) // ~20 m
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1063) // ~0.5 m (surfacing)
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1015) // surface tail
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1013) // surface tail
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1010) // below atmospheric

        let dive = try DiveParser.parse(data: Data(data))
        XCTAssertEqual(dive.samples.count, 6)
        // Last deep sample is index 1; keep one surfacing sample after it.
        XCTAssertEqual(dive.trimmedSamples.count, 3)
        XCTAssertEqual(dive.trimmedSamples.last?.time, 60)
    }

    func testTrimmedSamplesKeepsAllWhenNoTail() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 2013)
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 3013)
        let dive = try DiveParser.parse(data: Data(data))
        XCTAssertEqual(dive.trimmedSamples.count, 2)
    }

    func testDiveIsCodable() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        let dive = try DiveParser.parse(data: Data(data))
        let encoded = try JSONEncoder().encode(dive)
        let decoded = try JSONDecoder().decode(Dive.self, from: encoded)
        XCTAssertEqual(decoded, dive)
    }
}
