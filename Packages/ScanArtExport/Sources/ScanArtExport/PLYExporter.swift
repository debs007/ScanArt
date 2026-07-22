import Foundation
import ScanArtAlgorithms

/// ASCII PLY (Stanford Triangle Format) with per-vertex position, normal, AND
/// RGB color — PLY natively supports vertex color, which DXF/OBJ/STL don't
/// (or don't cleanly), making this the best format for taking the actual
/// heat-map-colored mesh into MeshLab, CloudCompare, Blender, etc.
public enum PLYExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        let mesh = payload.mesh
        let colorMapper = payload.colorMapper ?? .standard(desiredThicknessMM: 40, toleranceMM: 2)

        var lines: [String] = []
        lines.append("ply")
        lines.append("format ascii 1.0")
        lines.append("comment Exported by Scan Art — \(payload.projectName) / \(payload.scanLabel)")
        lines.append("element vertex \(mesh.vertexCount)")
        lines.append("property float x")
        lines.append("property float y")
        lines.append("property float z")
        lines.append("property float nx")
        lines.append("property float ny")
        lines.append("property float nz")
        lines.append("property uchar red")
        lines.append("property uchar green")
        lines.append("property uchar blue")
        lines.append("element face \(mesh.faceCount)")
        lines.append("property list uchar int vertex_indices")
        lines.append("end_header")

        for i in 0..<mesh.vertexCount {
            let p = mesh.vertices[i]
            let n = mesh.normals[i]
            let color: RGBAColor
            if let samples = payload.samples, i < samples.count, samples[i].isValid {
                color = colorMapper.color(for: Double(samples[i].thicknessMM))
            } else if payload.samples != nil {
                color = ThicknessColorMapper.noData
            } else {
                color = RGBAColor(r: 0.9, g: 0.9, b: 0.92)
            }
            let r = Int((color.r * 255).rounded()), g = Int((color.g * 255).rounded()), b = Int((color.b * 255).rounded())
            lines.append("\(p.x) \(p.y) \(p.z) \(n.x) \(n.y) \(n.z) \(r) \(g) \(b)")
        }

        for f in 0..<mesh.faceCount {
            let a = mesh.indices[f * 3], b = mesh.indices[f * 3 + 1], c = mesh.indices[f * 3 + 2]
            lines.append("3 \(a) \(b) \(c)")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .ascii)
    }
}
