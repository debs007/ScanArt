import XCTest
import simd
@testable import ScanArtAlgorithms

final class ICPAlignerTests: XCTestCase {

    /// Builds a synthetic "room corner" point cloud (two perpendicular planes,
    /// like a floor meeting a wall) — enough geometric variation for ICP to have
    /// a well-defined unique solution, unlike a single flat plane which is
    /// under-constrained (free to slide in-plane).
    private func syntheticReferenceCloud(pointsPerSide: Int = 20) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for i in 0..<pointsPerSide {
            for j in 0..<pointsPerSide {
                let u = Float(i) / Float(pointsPerSide - 1) * 2 - 1
                let v = Float(j) / Float(pointsPerSide - 1) * 2 - 1
                points.append(SIMD3<Float>(u, 0, v))        // floor, y = 0
                points.append(SIMD3<Float>(u, v + 1, -1))   // wall, z = -1
            }
        }
        return points
    }

    private func meshFrom(_ points: [SIMD3<Float>]) -> MeshBuffer {
        // ICP here only needs vertices; a degenerate/absent index buffer is fine
        // since alignment doesn't touch faces.
        MeshBuffer(vertices: points, normals: [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: points.count), indices: [])
    }

    func testRecoversKnownTranslation() {
        let reference = syntheticReferenceCloud()
        let knownTranslation = SIMD3<Float>(0.02, -0.01, 0.015) // 1-2cm, plausible relocalization drift
        var transform = simd_float4x4.identity
        transform.columns.3 = SIMD4<Float>(knownTranslation, 1)
        let moved = reference.map(transform.transformPoint)

        let result = ICPAligner.align(source: meshFrom(moved), target: meshFrom(reference))

        XCTAssertLessThan(result.rmse, 0.001, "RMSE should be near-zero for a perfectly translated synthetic cloud")
        let recoveredTranslation = result.transform.transformPoint(.zero)
        XCTAssertEqual(recoveredTranslation.x, -knownTranslation.x, accuracy: 0.002)
        XCTAssertEqual(recoveredTranslation.y, -knownTranslation.y, accuracy: 0.002)
        XCTAssertEqual(recoveredTranslation.z, -knownTranslation.z, accuracy: 0.002)
    }

    func testRecoversKnownSmallRotationAndTranslation() {
        let reference = syntheticReferenceCloud()
        let angle: Float = 0.05 // ~2.9 degrees, plausible small drift
        let rotation = simd_float4x4(simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
        var transform = rotation
        transform.columns.3 = SIMD4<Float>(0.01, 0, -0.005, 1)
        let moved = reference.map(transform.transformPoint)

        let result = ICPAligner.align(source: meshFrom(moved), target: meshFrom(reference))

        XCTAssertLessThan(result.rmse, 0.001)
        // Applying the recovered transform to `moved` should land back near `reference`.
        var maxResidual: Float = 0
        for (i, p) in moved.enumerated() {
            let corrected = result.transform.transformPoint(p)
            maxResidual = max(maxResidual, length(corrected - reference[i]))
        }
        XCTAssertLessThan(maxResidual, 0.005, "Every point should land within 5mm of its true correspondence")
    }

    func testInsufficientOverlapDoesNotCrash() {
        let tinyCloud = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0)]
        let result = ICPAligner.align(source: meshFrom(tinyCloud), target: meshFrom(tinyCloud))
        XCTAssertFalse(result.converged)
    }
}
