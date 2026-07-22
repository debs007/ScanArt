import simd
import ScanArtAlgorithms

/// Estimates "how much of the wall have you scanned" in real time. There's no
/// a-priori target area (the user hasn't declared wall dimensions), so this
/// projects the mesh onto its own dominant plane and compares meshed area to
/// the bounding rectangle of that projection — i.e. "how filled-in is the
/// rectangle you've been pointing the camera at". For a flat rectangular wall
/// this converges to ~100% as coverage completes; for irregular openings
/// (windows, alcoves) it plateaus below 100%, which is an acceptable
/// approximation for a live guidance signal (final coverage in the Analysis
/// screen instead uses the actual comparison sample validity ratio, which is
/// exact — see ThicknessStatistics.coveragePercent).
///
/// Takes a pre-converted `MeshBuffer` rather than raw `ARMeshAnchor` objects
/// so the caller controls where the (expensive) anchor→buffer conversion runs.
public struct ScanQualityAnalyzer {
    public init() {}

    /// Face count is capped by sampling every Nth face once the mesh gets large.
    /// Designed to run on a background thread — `MeshBuffer` is `Sendable`.
    public func estimateCoverage(mesh: MeshBuffer) -> Double {
        guard mesh.faceCount > 0 else { return 0 }

        let stride = max(1, mesh.faceCount / 4000) // cap real-time cost
        var normalSum = SIMD3<Float>.zero
        var sampledFaces: [Int] = []
        sampledFaces.reserveCapacity(mesh.faceCount / stride + 1)
        var f = 0
        while f < mesh.faceCount {
            sampledFaces.append(f)
            let a = mesh.vertices[Int(mesh.indices[f * 3])]
            let b = mesh.vertices[Int(mesh.indices[f * 3 + 1])]
            let c = mesh.vertices[Int(mesh.indices[f * 3 + 2])]
            normalSum += cross(b - a, c - a)
            f += stride
        }
        guard length(normalSum) > 1e-6 else { return 0 }
        let planeNormal = normalize(normalSum)

        // Build an orthonormal basis (u, v) spanning the plane.
        let arbitrary = abs(planeNormal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let u = normalize(cross(planeNormal, arbitrary))
        let v = cross(planeNormal, u)

        var minU: Float = .greatestFiniteMagnitude, maxU: Float = -.greatestFiniteMagnitude
        var minV: Float = .greatestFiniteMagnitude, maxV: Float = -.greatestFiniteMagnitude
        var meshedArea: Float = 0

        for f in sampledFaces {
            let a = mesh.vertices[Int(mesh.indices[f * 3])]
            let b = mesh.vertices[Int(mesh.indices[f * 3 + 1])]
            let c = mesh.vertices[Int(mesh.indices[f * 3 + 2])]
            for p in [a, b, c] {
                let pu = dot(p, u), pv = dot(p, v)
                minU = min(minU, pu); maxU = max(maxU, pu)
                minV = min(minV, pv); maxV = max(maxV, pv)
            }
            meshedArea += 0.5 * length(cross(b - a, c - a))
        }

        let rectArea = max((maxU - minU) * (maxV - minV), 1e-4)
        // Sampling reduced face count by `stride`; scale the area estimate back up.
        let scaledMeshedArea = meshedArea * Float(stride)
        let coverage = min(100, Double(scaledMeshedArea / rectArea) * 100)
        return coverage
    }
}
