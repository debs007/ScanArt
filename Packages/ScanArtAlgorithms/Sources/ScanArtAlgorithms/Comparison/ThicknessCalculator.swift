import simd

public struct ThicknessSample: Sendable {
    /// Point on the ORIGINAL (pre-plaster) wall surface — the thickness map is
    /// parameterized over the original wall, answering "how far did the surface
    /// move outward here?"
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let thicknessMM: Float
    /// True if a valid corresponding point was found on the rescan surface.
    public let isValid: Bool

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, thicknessMM: Float, isValid: Bool) {
        self.position = position
        self.normal = normal
        self.thicknessMM = thicknessMM
        self.isValid = isValid
    }
}

public enum ThicknessMethod: Sendable {
    /// Nearest-vertex projection onto the normal. O(n), good for live preview
    /// during a rescan where the mesh is still being built.
    case nearestNeighborProjection
    /// Ray-cast from each original-wall point along its normal into the rescan
    /// mesh, taking the true ray-triangle intersection distance. Slower, but not
    /// biased by rescan vertex density the way nearest-vertex projection can be
    /// on rough/lumpy plaster — this is what "Generate thickness map" (the final
    /// analysis step) uses.
    case rayMeshIntersection
}

public enum ThicknessCalculator {

    public struct Options: Sendable {
        public var method: ThicknessMethod = .rayMeshIntersection
        /// Cap on how far a ray/nearest-neighbor search looks before giving up on
        /// a sample point (meters). Keeps a hole in the rescan from reporting a
        /// bogus multi-meter "thickness" instead of just being marked invalid.
        public var maxSearchDistance: Float = 0.15
        public var cellSize: Float = 0.03
        /// Ray cast is tried along +normal and -normal; whichever hits first wins.
        /// This tolerates small alignment noise that flips which side is "outward".
        public var rayBothDirections: Bool = true

        public init() {}
    }

    /// Computes per-point thickness from `original` (pre-plaster) to `rescan`
    /// (post-plaster). Both meshes must already be in the same coordinate frame
    /// (post-alignment). Runs off the main thread via structured concurrency,
    /// chunked across original's vertices.
    public static func compute(
        original: MeshBuffer,
        rescan: MeshBuffer,
        options: Options = Options()
    ) async -> [ThicknessSample] {
        guard !original.vertices.isEmpty, !rescan.vertices.isEmpty else { return [] }

        switch options.method {
        case .nearestNeighborProjection:
            let grid = SpatialHashGrid(points: rescan.vertices, cellSize: options.cellSize)
            return await computeChunked(original: original) { range in
                nearestNeighborChunk(original: original, rescan: rescan, grid: grid, range: range, options: options)
            }
        case .rayMeshIntersection:
            let triangleGrid = TriangleSpatialHashGrid(mesh: rescan, cellSize: max(options.cellSize, 0.05))
            return await computeChunked(original: original) { range in
                rayCastChunk(original: original, rescan: rescan, triangleGrid: triangleGrid, range: range, options: options)
            }
        }
    }

    private static func computeChunked(
        original: MeshBuffer,
        work: @escaping (Range<Int>) -> [ThicknessSample]
    ) async -> [ThicknessSample] {
        let count = original.vertices.count
        let chunkSize = max(2000, count / 8) // ~8-way parallelism on typical hardware
        let ranges = stride(from: 0, to: count, by: chunkSize).map { start in
            start..<min(start + chunkSize, count)
        }

        var results = [ThicknessSample?](repeating: nil, count: 0)
        results.reserveCapacity(count)

        let chunks: [(Range<Int>, [ThicknessSample])] = await withTaskGroup(of: (Range<Int>, [ThicknessSample]).self) { group in
            for range in ranges {
                group.addTask { (range, work(range)) }
            }
            var collected: [(Range<Int>, [ThicknessSample])] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var ordered = [ThicknessSample](repeating: ThicknessSample(position: .zero, normal: .zero, thicknessMM: 0, isValid: false), count: count)
        for (range, samples) in chunks {
            for (offset, sample) in samples.enumerated() {
                ordered[range.lowerBound + offset] = sample
            }
        }
        _ = results
        return ordered
    }

    private static func nearestNeighborChunk(
        original: MeshBuffer,
        rescan: MeshBuffer,
        grid: SpatialHashGrid,
        range: Range<Int>,
        options: Options
    ) -> [ThicknessSample] {
        var samples: [ThicknessSample] = []
        samples.reserveCapacity(range.count)
        for i in range {
            let p0 = original.vertices[i]
            let n0 = original.normals[i]
            guard let match = grid.nearestNeighbor(to: p0, maxRadius: options.maxSearchDistance) else {
                samples.append(ThicknessSample(position: p0, normal: n0, thicknessMM: 0, isValid: false))
                continue
            }
            let p1 = rescan.vertices[Int(match.index)]
            // Signed projection onto the original surface's outward normal.
            let thicknessMeters = dot(p1 - p0, n0)
            samples.append(ThicknessSample(position: p0, normal: n0, thicknessMM: thicknessMeters * 1000, isValid: true))
        }
        return samples
    }

    private static func rayCastChunk(
        original: MeshBuffer,
        rescan: MeshBuffer,
        triangleGrid: TriangleSpatialHashGrid,
        range: Range<Int>,
        options: Options
    ) -> [ThicknessSample] {
        var samples: [ThicknessSample] = []
        samples.reserveCapacity(range.count)
        for i in range {
            let p0 = original.vertices[i]
            let n0 = original.normals[i]

            // Track outward (+n0) and inward (-n0) hits separately so the
            // outward direction always wins when both are found. The previous
            // single-bestT approach compared raw positive t values from both
            // directions, letting an inward hit replace a valid outward hit
            // (or vice-versa) based on raw distance rather than direction.
            var bestOutward: Float? = nil   // distance along +n0 (positive → surface grew)
            var bestInward: Float? = nil    // distance along -n0 (positive raw distance)

            let candidates = triangleGrid.candidateFaces(near: p0, searchRadius: options.maxSearchDistance)
            for f in candidates {
                let a = rescan.vertices[Int(rescan.indices[f * 3])]
                let b = rescan.vertices[Int(rescan.indices[f * 3 + 1])]
                let c = rescan.vertices[Int(rescan.indices[f * 3 + 2])]

                if let t = RayTriangleIntersection.test(origin: p0, direction: n0, a: a, b: b, c: c),
                   t <= options.maxSearchDistance {
                    if bestOutward == nil || t < bestOutward! { bestOutward = t }
                }
                if options.rayBothDirections,
                   let t = RayTriangleIntersection.test(origin: p0, direction: -n0, a: a, b: b, c: c),
                   t <= options.maxSearchDistance {
                    if bestInward == nil || t < bestInward! { bestInward = t }
                }
            }

            // Prefer outward hit (surface grew). Only use inward hit as fallback
            // when there is genuinely no outward intersection — this prevents a
            // closer back-face hit from masking a valid thickness measurement.
            if let t = bestOutward {
                samples.append(ThicknessSample(position: p0, normal: n0, thicknessMM: t * 1000, isValid: true))
            } else if let t = bestInward {
                samples.append(ThicknessSample(position: p0, normal: n0, thicknessMM: -t * 1000, isValid: true))
            } else {
                samples.append(ThicknessSample(position: p0, normal: n0, thicknessMM: 0, isValid: false))
            }
        }
        return samples
    }
}

/// Standard Möller–Trumbore ray-triangle intersection. Returns the distance
/// along `direction` to the hit point, or nil for no intersection / triangle
/// behind the ray origin.
enum RayTriangleIntersection {
    static func test(origin: SIMD3<Float>, direction: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> Float? {
        let epsilon: Float = 1e-7
        let edge1 = b - a
        let edge2 = c - a
        let h = cross(direction, edge2)
        let det = dot(edge1, h)
        if abs(det) < epsilon { return nil } // ray parallel to triangle
        let invDet = 1 / det
        let s = origin - a
        let u = invDet * dot(s, h)
        if u < 0 || u > 1 { return nil }
        let q = cross(s, edge1)
        let v = invDet * dot(direction, q)
        if v < 0 || u + v > 1 { return nil }
        let t = invDet * dot(edge2, q)
        return t > epsilon ? t : nil
    }
}
