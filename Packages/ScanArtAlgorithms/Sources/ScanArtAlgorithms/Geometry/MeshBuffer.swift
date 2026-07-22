import simd

/// Semantic classification of a face, mirroring ARKit's `ARMeshClassification`
/// without taking a dependency on ARKit. `ScanArtAR` maps `ARMeshClassification`
/// into this type at capture time.
///
/// This matters beyond labeling: `.wall` faces are the *measurement target*
/// (what we compute plaster thickness on), while `.floor` / `.ceiling` /
/// `.window` / `.door` are *stable reference* faces that don't move between
/// scans and are used to anchor alignment. See ICPAligner.
public enum MeshRegionClass: UInt8, Sendable, Codable, CaseIterable {
    case unknown = 0
    case wall
    case floor
    case ceiling
    case table
    case seat
    case window
    case door

    /// Faces that should NOT move between the pre-plaster and post-plaster scan,
    /// and are therefore safe to align on.
    public var isStableReference: Bool {
        switch self {
        case .floor, .ceiling, .window, .door: return true
        default: return false
        }
    }

    public var isMeasurementTarget: Bool { self == .wall }
}

/// A plain-data triangle mesh in world space (meters, matching ARKit's native unit).
/// This is the single geometric currency every package speaks — ARKit anchors,
/// the renderer, the exporters, and the algorithms all consume/produce this type.
public struct MeshBuffer: Sendable {
    /// World-space vertex positions, in meters.
    public var vertices: [SIMD3<Float>]
    /// World-space per-vertex normals (unit length).
    public var normals: [SIMD3<Float>]
    /// Triangle list: 3 indices per face, into `vertices`/`normals`.
    public var indices: [UInt32]
    /// Optional per-FACE classification (ARKit reports classification per face,
    /// not per vertex). Empty if classification wasn't captured. Count, when
    /// present, equals `faceCount`.
    public var faceClassifications: [MeshRegionClass]

    public init(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        indices: [UInt32],
        faceClassifications: [MeshRegionClass] = []
    ) {
        self.vertices = vertices
        self.normals = normals
        self.indices = indices
        self.faceClassifications = faceClassifications
    }

    public var vertexCount: Int { vertices.count }
    public var faceCount: Int { indices.count / 3 }

    /// Classification for vertex `i`, derived by majority vote over incident faces.
    /// Falls back to `.unknown` if no classification data is present.
    public func vertexClassifications() -> [MeshRegionClass] {
        guard !faceClassifications.isEmpty else {
            return [MeshRegionClass](repeating: .unknown, count: vertexCount)
        }
        var votes = [[MeshRegionClass.RawValue: Int]](repeating: [:], count: vertexCount)
        for f in 0..<faceCount {
            let cls = faceClassifications[f]
            for k in 0..<3 {
                let vi = Int(indices[f * 3 + k])
                votes[vi][cls.rawValue, default: 0] += 1
            }
        }
        return votes.map { dict in
            guard let best = dict.max(by: { $0.value < $1.value })?.key,
                  let cls = MeshRegionClass(rawValue: best) else { return .unknown }
            return cls
        }
    }

    public func boundingBox() -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard !vertices.isEmpty else { return (.zero, .zero) }
        var lo = vertices[0]
        var hi = vertices[0]
        for v in vertices {
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        return (lo, hi)
    }

    /// Returns a copy transformed by `matrix` (vertices as points, normals as directions).
    public func transformed(by matrix: simd_float4x4) -> MeshBuffer {
        MeshBuffer(
            vertices: vertices.map(matrix.transformPoint),
            normals: normals.map { normalize(matrix.transformDirection($0)) },
            indices: indices,
            faceClassifications: faceClassifications
        )
    }

    /// Extracts the subset of faces (and their referenced vertices) matching `predicate`.
    /// Used to isolate e.g. just the `.wall` faces for measurement, or just the
    /// stable-reference faces for alignment. Rebuilds a compact index buffer.
    public func filteredByFace(_ predicate: (MeshRegionClass) -> Bool) -> MeshBuffer {
        guard !faceClassifications.isEmpty else { return self }
        var remap: [Int: UInt32] = [:]
        var newVertices: [SIMD3<Float>] = []
        var newNormals: [SIMD3<Float>] = []
        var newIndices: [UInt32] = []
        var newClasses: [MeshRegionClass] = []

        for f in 0..<faceCount where predicate(faceClassifications[f]) {
            for k in 0..<3 {
                let vi = Int(indices[f * 3 + k])
                if let mapped = remap[vi] {
                    newIndices.append(mapped)
                } else {
                    let newIndex = UInt32(newVertices.count)
                    remap[vi] = newIndex
                    newVertices.append(vertices[vi])
                    newNormals.append(normals[vi])
                    newIndices.append(newIndex)
                }
            }
            newClasses.append(faceClassifications[f])
        }
        return MeshBuffer(vertices: newVertices, normals: newNormals, indices: newIndices, faceClassifications: newClasses)
    }
}
