import simd

/// A uniform-cell spatial hash over a point set, giving average O(1) nearest-neighbor
/// queries. Chosen over a k-d tree deliberately: LiDAR mesh vertices from ARKit are
/// roughly uniform-density (driven by the scene reconstruction voxel size), which is
/// exactly the case a uniform grid excels at, and it's simpler to get right than a
/// balanced tree — important when this code has never touched a compiler.
public struct SpatialHashGrid {
    private let points: [SIMD3<Float>]
    private let cellSize: Float
    private let inverseCellSize: Float
    private var buckets: [Int64: [Int32]] = [:]

    public init(points: [SIMD3<Float>], cellSize: Float) {
        self.points = points
        self.cellSize = max(cellSize, 1e-4)
        self.inverseCellSize = 1 / self.cellSize
        buckets.reserveCapacity(points.count)
        for (i, p) in points.enumerated() {
            let key = Self.cellKey(for: p, inverseCellSize: inverseCellSize)
            buckets[key, default: []].append(Int32(i))
        }
    }

    private static func cellKey(for p: SIMD3<Float>, inverseCellSize: Float) -> Int64 {
        // Pack three 20-bit signed cell coordinates into an Int64. Range is generous
        // (+/- ~500,000 cells, i.e. +/- multiple kilometers at cm cell size) — far
        // beyond any indoor scan.
        let cx = Int64((p.x * inverseCellSize).rounded(.down))
        let cy = Int64((p.y * inverseCellSize).rounded(.down))
        let cz = Int64((p.z * inverseCellSize).rounded(.down))
        let mask: Int64 = 0xFFFFF // 20 bits
        return ((cx & mask) << 40) | ((cy & mask) << 20) | (cz & mask)
    }

    private func cellCoord(for p: SIMD3<Float>) -> (Int, Int, Int) {
        (Int((p.x * inverseCellSize).rounded(.down)),
         Int((p.y * inverseCellSize).rounded(.down)),
         Int((p.z * inverseCellSize).rounded(.down)))
    }

    /// Finds the nearest point to `query`, expanding the search ring outward until
    /// a candidate is found or `maxRadius` is exceeded. Returns nil if nothing is
    /// within `maxRadius`.
    public func nearestNeighbor(to query: SIMD3<Float>, maxRadius: Float) -> (index: Int32, distanceSquared: Float)? {
        let (cx, cy, cz) = cellCoord(for: query)
        var best: (index: Int32, distanceSquared: Float)? = nil
        let maxRing = Int((maxRadius * inverseCellSize).rounded(.up)) + 1

        var ring = 0
        while ring <= maxRing {
            var foundAnyInRing = false
            for dx in -ring...ring {
                for dy in -ring...ring {
                    for dz in -ring...ring {
                        // Only visit the shell of this ring (already-visited inner
                        // cells were covered by smaller `ring` values).
                        guard max(abs(dx), max(abs(dy), abs(dz))) == ring else { continue }
                        let mask: Int64 = 0xFFFFF
                        let key = ((Int64(cx + dx) & mask) << 40) | ((Int64(cy + dy) & mask) << 20) | (Int64(cz + dz) & mask)
                        guard let bucket = buckets[key] else { continue }
                        foundAnyInRing = true
                        for idx in bucket {
                            let d2 = simd_length_squared(points[Int(idx)] - query)
                            if d2 <= maxRadius * maxRadius, (best == nil || d2 < best!.distanceSquared) {
                                best = (idx, d2)
                            }
                        }
                    }
                }
            }
            // Once we have a candidate, we still need to expand one extra ring
            // beyond it (a closer point could sit just across a cell boundary),
            // then stop.
            if best != nil, Float(ring) * cellSize > sqrt(best!.distanceSquared) {
                break
            }
            _ = foundAnyInRing
            ring += 1
        }
        return best
    }

    /// Returns all point indices within `radius` of `query` (unsorted).
    public func neighbors(within radius: Float, of query: SIMD3<Float>) -> [Int32] {
        let (cx, cy, cz) = cellCoord(for: query)
        let ring = Int((radius * inverseCellSize).rounded(.up)) + 1
        var result: [Int32] = []
        let r2 = radius * radius
        for dx in -ring...ring {
            for dy in -ring...ring {
                for dz in -ring...ring {
                    let mask: Int64 = 0xFFFFF
                    let key = ((Int64(cx + dx) & mask) << 40) | ((Int64(cy + dy) & mask) << 20) | (Int64(cz + dz) & mask)
                    guard let bucket = buckets[key] else { continue }
                    for idx in bucket where simd_length_squared(points[Int(idx)] - query) <= r2 {
                        result.append(idx)
                    }
                }
            }
        }
        return result
    }
}

/// Same idea as `SpatialHashGrid`, but buckets triangles by centroid so a ray can
/// quickly gather a small candidate set instead of testing every triangle in the mesh.
public struct TriangleSpatialHashGrid {
    private let mesh: MeshBuffer
    private let grid: SpatialHashGrid
    private let centroids: [SIMD3<Float>]

    public init(mesh: MeshBuffer, cellSize: Float) {
        self.mesh = mesh
        var centroids: [SIMD3<Float>] = []
        centroids.reserveCapacity(mesh.faceCount)
        for f in 0..<mesh.faceCount {
            let a = mesh.vertices[Int(mesh.indices[f * 3])]
            let b = mesh.vertices[Int(mesh.indices[f * 3 + 1])]
            let c = mesh.vertices[Int(mesh.indices[f * 3 + 2])]
            centroids.append((a + b + c) / 3)
        }
        self.centroids = centroids
        self.grid = SpatialHashGrid(points: centroids, cellSize: cellSize)
    }

    /// Candidate face indices near `point`, expanding search radius until at least
    /// one ring beyond the first hit (mirrors `SpatialHashGrid.nearestNeighbor`).
    public func candidateFaces(near point: SIMD3<Float>, searchRadius: Float) -> [Int] {
        grid.neighbors(within: searchRadius, of: point).map { Int($0) }
    }
}
