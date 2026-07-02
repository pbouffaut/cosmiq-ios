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
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513) // ~5 m, 28.5 C
        data += makeSample(temperatureDeciC: 280, pressureMillibar: 3013) // ~19.9 m
        data += [0xFF, 0xFF, 0xFF, 0xFF] // padding must be skipped
        data += makeSample(temperatureDeciC: 282, pressureMillibar: 2013) // ~9.9 m

        let dive = try DiveParser.parse(data: Data(data))

        XCTAssertEqual(dive.activity, .scuba)
        XCTAssertEqual(dive.oxygenPercent, 32)
        XCTAssertEqual(dive.atmosphericMillibar, 1013)
        XCTAssertEqual(dive.duration, 45 * 60, "scuba dive time is stored in minutes")
        XCTAssertEqual(dive.sampleIntervalSeconds, 20)
        XCTAssertEqual(dive.samples.count, 3)

        // Max depth: (3013-1013) mbar over salt water = 2000*100/(1025*9.80665) m
        XCTAssertEqual(dive.maxDepth, 19.90, accuracy: 0.01)

        XCTAssertEqual(dive.samples[0].time, 20)
        XCTAssertEqual(dive.samples[0].temperature, 28.5, accuracy: 0.001)
        XCTAssertEqual(dive.samples[0].depth, 4.97, accuracy: 0.01)
        // Padding does not advance time.
        XCTAssertEqual(dive.samples[2].time, 60)

        // Date comes from the odd header layout (minute before hour).
        let calendar = Calendar.current
        let start = try XCTUnwrap(dive.start)
        XCTAssertEqual(calendar.component(.year, from: start), 2026)
        XCTAssertEqual(calendar.component(.month, from: start), 6)
        XCTAssertEqual(calendar.component(.day, from: start), 15)
        XCTAssertEqual(calendar.component(.hour, from: start), 14)
        XCTAssertEqual(calendar.component(.minute, from: start), 30)
    }

    func testFreediveDurationIsSeconds() throws {
        let data = makeHeader(activity: .freedive, duration: 95)
        let dive = try DiveParser.parse(data: Data(data))
        XCTAssertEqual(dive.duration, 95)
        XCTAssertTrue(dive.samples.isEmpty)
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
        XCTAssertTrue(csv.contains("20,4.97,28.50"))
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

    func testDiveIsCodable() throws {
        var data = makeHeader()
        data += makeSample(temperatureDeciC: 285, pressureMillibar: 1513)
        let dive = try DiveParser.parse(data: Data(data))
        let encoded = try JSONEncoder().encode(dive)
        let decoded = try JSONDecoder().decode(Dive.self, from: encoded)
        XCTAssertEqual(decoded, dive)
    }
}
