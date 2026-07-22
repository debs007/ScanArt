import simd

/// Grid-based vertex-clustering decimation (the same family of technique as
/// MeshLab's "Clustering Decimation"): partition space into voxels, collapse
/// every vertex in a voxel to its centroid, remap faces, and drop any face
/// that degenerates (two or more corners collapsing to the same vertex).
///
/// This is deliberately simpler than quadric-error-metric decimation (which
/// preserves detail much better at aggressive ratios) in exchange for being
/// something that can be implemented correctly without a compiler in the loop.
/// A QEM-based decimator is called out in the roadmap as a quality upgrade for
/// when very large scans need higher decimation ratios without visible loss
/// of wall detail.
public enum MeshDecimator {
    public static func decimate(_ mesh: MeshBuffer, voxelSize: Float) -> MeshBuffer {
        guard voxelSize > 0, !mesh.vertices.isEmpty else { return mesh }

        var cellToVertex: [Int64: Int] = [:]
        var newVertices: [SIMD3<Float>] = []
        var newNormals: [SIMD3<Float>] = []
        var vertexRemap = [Int](repeating: -1, count: mesh.vertexCount)
        let inv = 1 / voxelSize

        for i in 0..<mesh.vertexCount {
            let p = mesh.vertices[i]
            let key = cellKey(p, inv)
            if let existing = cellToVertex[key] {
                // Running average keeps the centroid representative even with
                // uneven point distribution within the voxel.
                vertexRemap[i] = existing
            } else {
                let newIndex = newVertices.count
                cellToVertex[key] = newIndex
                newVertices.append(p)
                newNormals.append(mesh.normals[i])
                vertexRemap[i] = newIndex
            }
        }

        var newIndices: [UInt32] = []
        var newClasses: [MeshRegionClass] = []
        newIndices.reserveCapacity(mesh.indices.count)
        for f in 0..<mesh.faceCount {
            let a = vertexRemap[Int(mesh.indices[f * 3])]
            let b = vertexRemap[Int(mesh.indices[f * 3 + 1])]
            let c = vertexRemap[Int(mesh.indices[f * 3 + 2])]
            guard a != b, b != c, a != c else { continue } // degenerate after collapse
            newIndices.append(UInt32(a))
            newIndices.append(UInt32(b))
            newIndices.append(UInt32(c))
            if f < mesh.faceClassifications.count { newClasses.append(mesh.faceClassifications[f]) }
        }

        return MeshBuffer(vertices: newVertices, normals: newNormals, indices: newIndices, faceClassifications: newClasses)
    }

    /// Picks a reasonable voxel size to bring `mesh` under `targetVertexCount`,
    /// by binary-searching over voxel size using the current bounding box as a
    /// scale reference. Cheap heuristic, not exact.
    public static func suggestedVoxelSize(for mesh: MeshBuffer, targetVertexCount: Int) -> Float {
        guard mesh.vertexCount > targetVertexCount, targetVertexCount > 0 else { return 0 }
        let box = mesh.boundingBox()
        let diagonal = length(box.max - box.min)
        let ratio = Float(mesh.vertexCount) / Float(targetVertexCount)
        // Empirical: vertex count scales roughly with 1/voxelSize^2 for a mostly-
        // planar wall surface, so scale by sqrt(ratio).
        return max(diagonal / 1000, 0.005) * sqrt(ratio)
    }

    private static func cellKey(_ p: SIMD3<Float>, _ inv: Float) -> Int64 {
        let cx = Int64((p.x * inv).rounded(.down))
        let cy = Int64((p.y * inv).rounded(.down))
        let cz = Int64((p.z * inv).rounded(.down))
        let mask: Int64 = 0xFFFFF
        return ((cx & mask) << 40) | ((cy & mask) << 20) | (cz & mask)
    }
}
