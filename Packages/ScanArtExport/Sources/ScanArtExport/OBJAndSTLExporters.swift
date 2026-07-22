import Foundation
import ScanArtAlgorithms

/// Standard Wavefront OBJ: positions, normals, and triangle faces referencing
/// both. Geometry-only by design — OBJ's vertex-color extension (`v x y z r
/// g b`) isn't part of the official spec and some parsers reject the extra
/// fields, so color-carrying export should go through PLY or DXF instead.
public enum OBJExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        let mesh = payload.mesh
        var lines: [String] = []
        lines.append("# Exported by Scan Art — \(payload.projectName) / \(payload.scanLabel)")
        lines.append("o \(sanitized(payload.scanLabel))")

        for v in mesh.vertices { lines.append("v \(v.x) \(v.y) \(v.z)") }
        for n in mesh.normals { lines.append("vn \(n.x) \(n.y) \(n.z)") }
        for f in 0..<mesh.faceCount {
            // OBJ indices are 1-based.
            let a = mesh.indices[f * 3] + 1, b = mesh.indices[f * 3 + 1] + 1, c = mesh.indices[f * 3 + 2] + 1
            lines.append("f \(a)//\(a) \(b)//\(b) \(c)//\(c)")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .ascii)
    }

    private static func sanitized(_ name: String) -> String {
        name.isEmpty ? "ScanArtMesh" : name.replacingOccurrences(of: " ", with: "_")
    }
}

/// Binary STL: 80-byte header, uint32 triangle count, then per triangle a
/// facet normal + 3 vertices (12 bytes each, little-endian float32) + a
/// 2-byte attribute count (0). Geometry-only — the STL spec has no color.
public enum STLExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        let mesh = payload.mesh
        var data = Data(count: 80) // header, left zeroed
        data.append(contentsOf: withUnsafeBytes(of: UInt32(mesh.faceCount).littleEndian) { Array($0) })

        for f in 0..<mesh.faceCount {
            let ia = Int(mesh.indices[f * 3]), ib = Int(mesh.indices[f * 3 + 1]), ic = Int(mesh.indices[f * 3 + 2])
            let a = mesh.vertices[ia], b = mesh.vertices[ib], c = mesh.vertices[ic]
            let normal = mesh.normals[ia] // per-facet normal; vertex normal is a fine approximation for a dense LiDAR mesh

            appendFloat32Vector(normal, to: &data)
            appendFloat32Vector(a, to: &data)
            appendFloat32Vector(b, to: &data)
            appendFloat32Vector(c, to: &data)
            data.append(contentsOf: [0, 0]) // attribute byte count
        }

        try data.write(to: url, options: .atomic)
    }

    private static func appendFloat32Vector(_ v: SIMD3<Float>, to data: inout Data) {
        for component in [v.x, v.y, v.z] {
            data.append(contentsOf: withUnsafeBytes(of: component.bitPattern.littleEndian) { Array($0) })
        }
    }
}
