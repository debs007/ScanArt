import simd

public enum SurfaceAreaCalculator {

    /// Total mesh surface area in square meters (sum of triangle areas via the
    /// cross-product formula).
    public static func totalAreaSquareMeters(_ mesh: MeshBuffer) -> Double {
        var total: Double = 0
        for f in 0..<mesh.faceCount {
            total += Double(triangleArea(mesh, face: f))
        }
        return total
    }

    /// Per-vertex "area of influence": each triangle contributes 1/3 of its area
    /// to each of its three corners. This is the standard barycentric area
    /// weighting used to turn a per-vertex quantity (like thickness) into a
    /// volume integral — see VolumeCalculator.
    public static func vertexAreas(_ mesh: MeshBuffer) -> [Float] {
        var areas = [Float](repeating: 0, count: mesh.vertexCount)
        for f in 0..<mesh.faceCount {
            let area = triangleArea(mesh, face: f)
            let third = area / 3
            areas[Int(mesh.indices[f * 3])] += third
            areas[Int(mesh.indices[f * 3 + 1])] += third
            areas[Int(mesh.indices[f * 3 + 2])] += third
        }
        return areas
    }

    private static func triangleArea(_ mesh: MeshBuffer, face: Int) -> Float {
        let a = mesh.vertices[Int(mesh.indices[face * 3])]
        let b = mesh.vertices[Int(mesh.indices[face * 3 + 1])]
        let c = mesh.vertices[Int(mesh.indices[face * 3 + 2])]
        return 0.5 * length(cross(b - a, c - a))
    }
}
