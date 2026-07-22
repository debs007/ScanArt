import XCTest
import simd
@testable import ScanArtAlgorithms

final class ThicknessCalculatorTests: XCTestCase {

    /// A flat, triangulated NxN grid in the XZ plane at height `y`, normal +Y —
    /// stands in for a LiDAR-scanned wall (in this local frame, "outward" is +Y).
    private func gridPlane(size: Int, spacing: Float, y: Float) -> MeshBuffer {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for i in 0..<size {
            for j in 0..<size {
                vertices.append(SIMD3<Float>(Float(i) * spacing, y, Float(j) * spacing))
                normals.append(SIMD3<Float>(0, 1, 0))
            }
        }
        var indices: [UInt32] = []
        for i in 0..<(size - 1) {
            for j in 0..<(size - 1) {
                let a = UInt32(i * size + j)
                let b = UInt32(i * size + j + 1)
                let c = UInt32((i + 1) * size + j)
                let d = UInt32((i + 1) * size + j + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        return MeshBuffer(vertices: vertices, normals: normals, indices: indices)
    }

    func testRayCastRecoversKnownOffset_4cm() async {
        let original = gridPlane(size: 12, spacing: 0.05, y: 0)      // pre-plaster wall
        let rescan = gridPlane(size: 12, spacing: 0.05, y: 0.04)     // post-plaster, +4cm

        var options = ThicknessCalculator.Options()
        options.method = .rayMeshIntersection
        let samples = await ThicknessCalculator.compute(original: original, rescan: rescan, options: options)

        let valid = samples.filter(\.isValid)
        XCTAssertFalse(valid.isEmpty)
        for s in valid {
            XCTAssertEqual(s.thicknessMM, 40, accuracy: 0.5, "Every interior sample should read ~40mm")
        }
    }

    func testNearestNeighborRecoversKnownOffset_15mm() async {
        let original = gridPlane(size: 10, spacing: 0.02, y: 0)
        let rescan = gridPlane(size: 10, spacing: 0.02, y: 0.015)    // +15mm

        var options = ThicknessCalculator.Options()
        options.method = .nearestNeighborProjection
        let samples = await ThicknessCalculator.compute(original: original, rescan: rescan, options: options)

        let valid = samples.filter(\.isValid)
        XCTAssertFalse(valid.isEmpty)
        let average = valid.reduce(Float(0)) { $0 + $1.thicknessMM } / Float(valid.count)
        XCTAssertEqual(average, 15, accuracy: 1.0)
    }

    func testNoCorrespondingSurfaceMarksInvalidRatherThanExtrapolating() async {
        let original = gridPlane(size: 8, spacing: 0.05, y: 0)
        // Rescan is far enough away that nothing should be within the search radius.
        let rescan = gridPlane(size: 8, spacing: 0.05, y: 5.0)

        let samples = await ThicknessCalculator.compute(original: original, rescan: rescan)
        XCTAssertTrue(samples.allSatisfy { !$0.isValid })
    }

    func testVolumeMatchesAreaTimesThickness() async {
        // A 0.5m x 0.5m wall, uniform 4cm thickness -> volume should be ~0.5*0.5*0.04 = 0.01 m^3.
        let spacing: Float = 0.05
        let size = 11 // (11-1)*0.05 = 0.5m square
        let original = gridPlane(size: size, spacing: spacing, y: 0)
        let rescan = gridPlane(size: size, spacing: spacing, y: 0.04)

        let samples = await ThicknessCalculator.compute(original: original, rescan: rescan)
        let vertexAreas = SurfaceAreaCalculator.vertexAreas(original)
        let volume = VolumeCalculator.computeCubicMeters(samples: samples, vertexAreas: vertexAreas)

        XCTAssertEqual(volume, 0.01, accuracy: 0.001)
    }
}
