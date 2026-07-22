import XCTest
@testable import ScanArtAlgorithms

final class ColorMapperTests: XCTestCase {

    func testOnTargetIsGreenish() {
        let mapper = ThicknessColorMapper.standard(desiredThicknessMM: 40, toleranceMM: 2)
        let color = mapper.color(for: 40)
        XCTAssertGreaterThan(color.g, color.r, "On-target thickness should read closer to green than red")
        XCTAssertGreaterThan(color.g, color.b)
    }

    func testVeryThinIsBlueDominant() {
        let mapper = ThicknessColorMapper.standard(desiredThicknessMM: 40, toleranceMM: 2)
        let color = mapper.color(for: 0)
        XCTAssertGreaterThan(color.b, color.g)
        XCTAssertGreaterThan(color.b, color.r)
    }

    func testExtremelyThickIsRedOrPurpleDominant() {
        let mapper = ThicknessColorMapper.standard(desiredThicknessMM: 40, toleranceMM: 2)
        let color = mapper.color(for: 200)
        XCTAssertGreaterThan(color.r, color.g, "Very thick readings should not read as green/on-target")
    }

    func testValuesBeyondLastStopClampRatherThanExtrapolate() {
        let mapper = ThicknessColorMapper.standard(desiredThicknessMM: 40, toleranceMM: 2)
        let farBeyond = mapper.color(for: 100_000)
        let atLastStop = mapper.color(for: mapper.stops.last!.thicknessMM)
        XCTAssertEqual(farBeyond, atLastStop)
    }

    func testMonotonicRedChannelAroundTransitionFromGreenToYellow() {
        let mapper = ThicknessColorMapper.standard(desiredThicknessMM: 40, toleranceMM: 2)
        let greenR = mapper.color(for: 41).r
        let yellowR = mapper.color(for: 43).r
        XCTAssertLessThanOrEqual(greenR, yellowR + 0.001)
    }
}
