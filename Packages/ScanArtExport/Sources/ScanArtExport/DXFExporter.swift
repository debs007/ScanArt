import Foundation
import ScanArtAlgorithms

/// Writes an ASCII DXF using only the well-established AC1009 (R12) entity
/// subset — HEADER + TABLES (LAYER) + ENTITIES with `3DFACE`. This is
/// deliberately the most conservative DXF dialect rather than a newer one:
/// R12's ENTITIES/3DFACE structure is the subset every major CAD package
/// (AutoCAD, Civil3D, Revit's DXF import, BricsCAD) has read reliably for
/// decades, which matters more here than any modern-DXF feature.
///
/// Geometry is preserved exactly (one 3DFACE per source triangle, real-world
/// coordinates, no simplification). Color is carried via layers: each face is
/// written to a layer named after its thickness band, colored with the
/// nearest AutoCAD Color Index (ACI) to that band's heat-map color, so
/// opening the file in any of the four target applications shows the
/// thickness classification without needing per-vertex color support (which
/// plain DXF doesn't have).
public enum DXFExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        var lines: [String] = []

        appendHeader(&lines)
        let layers = try appendLayerTable(&lines, payload: payload)
        appendEntities(&lines, payload: payload, layers: layers)
        appendEOF(&lines)

        let content = lines.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .ascii)
    }

    // MARK: - HEADER

    private static func appendHeader(_ lines: inout [String]) {
        group(&lines, 0, "SECTION")
        group(&lines, 2, "HEADER")
        group(&lines, 9, "$ACADVER")
        group(&lines, 1, "AC1009")
        group(&lines, 9, "$INSUNITS")
        group(&lines, 70, "6") // 6 = meters, matching our internal coordinate unit
        group(&lines, 0, "ENDSEC")
    }

    // MARK: - TABLES / LAYER

    private struct Layer {
        let name: String
        let aci: Int
    }

    /// One layer per color stop in the project's palette, so the DXF's layer
    /// list mirrors the on-screen legend.
    private static func appendLayerTable(_ lines: inout [String], payload: ExportPayload) throws -> [Layer] {
        let stops = (payload.colorMapper ?? .standard(desiredThicknessMM: 40, toleranceMM: 2)).stops
        var layers = stops.enumerated().map { index, stop in
            Layer(name: sanitizedLayerName("THK_\(index)_\(stop.label)"), aci: nearestACI(stop.color))
        }
        layers.append(Layer(name: "NO_DATA", aci: 8)) // dark gray
        layers.append(Layer(name: "GEOMETRY", aci: 7)) // plain white/default, used when no color data at all

        group(&lines, 0, "SECTION")
        group(&lines, 2, "TABLES")
        group(&lines, 0, "TABLE")
        group(&lines, 2, "LAYER")
        group(&lines, 70, "\(layers.count)")
        for layer in layers {
            group(&lines, 0, "LAYER")
            group(&lines, 2, layer.name)
            group(&lines, 70, "0")
            group(&lines, 62, "\(layer.aci)")
            group(&lines, 6, "CONTINUOUS")
        }
        group(&lines, 0, "ENDTAB")
        group(&lines, 0, "ENDSEC")
        return layers
    }

    // MARK: - ENTITIES

    private static func appendEntities(_ lines: inout [String], payload: ExportPayload, layers: [Layer]) {
        group(&lines, 0, "SECTION")
        group(&lines, 2, "ENTITIES")

        let mesh = payload.mesh
        let stops = (payload.colorMapper ?? .standard(desiredThicknessMM: 40, toleranceMM: 2)).stops

        for f in 0..<mesh.faceCount {
            let ia = Int(mesh.indices[f * 3])
            let ib = Int(mesh.indices[f * 3 + 1])
            let ic = Int(mesh.indices[f * 3 + 2])
            let a = mesh.vertices[ia]
            let b = mesh.vertices[ib]
            let c = mesh.vertices[ic]

            let layerName = layerName(forVertex: ia, samples: payload.samples, stops: stops, layers: layers)

            group(&lines, 0, "3DFACE")
            group(&lines, 8, layerName)
            group(&lines, 10, format(a.x)); group(&lines, 20, format(a.y)); group(&lines, 30, format(a.z))
            group(&lines, 11, format(b.x)); group(&lines, 21, format(b.y)); group(&lines, 31, format(b.z))
            group(&lines, 12, format(c.x)); group(&lines, 22, format(c.y)); group(&lines, 32, format(c.z))
            // 4th corner repeats the 3rd — standard way to represent a triangle as a 3DFACE.
            group(&lines, 13, format(c.x)); group(&lines, 23, format(c.y)); group(&lines, 33, format(c.z))
        }

        group(&lines, 0, "ENDSEC")
    }

    private static func layerName(forVertex vertexIndex: Int, samples: [ThicknessSample]?, stops: [ColorStop], layers: [Layer]) -> String {
        guard let samples, vertexIndex < samples.count else {
            return layers.first { $0.name == "GEOMETRY" }?.name ?? "0"
        }
        let sample = samples[vertexIndex]
        guard sample.isValid else { return layers.first { $0.name == "NO_DATA" }?.name ?? "0" }

        // Find the closest stop by thickness (matches the coloring the viewer used).
        var bestIndex = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (i, stop) in stops.enumerated() {
            let delta = abs(stop.thicknessMM - Double(sample.thicknessMM))
            if delta < bestDelta { bestDelta = delta; bestIndex = i }
        }
        return layers[bestIndex].name
    }

    // MARK: - Footer

    private static func appendEOF(_ lines: inout [String]) {
        group(&lines, 0, "EOF")
    }

    // MARK: - Helpers

    private static func group(_ lines: inout [String], _ code: Int, _ value: String) {
        lines.append(String(code))
        lines.append(value)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.6f", value)
    }

    private static func sanitizedLayerName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(String(cleaned).prefix(31)) // DXF R12 layer name limit
    }

    /// Maps an RGB color to the nearest of the 16 standard AutoCAD Color Index
    /// entries most CAD tools render distinctly and legibly. This is an
    /// approximation by design (ACI is a fixed 255-entry palette, and matching
    /// it exactly needs the real ACI RGB table) — documented in ARCHITECTURE.md
    /// as a Phase 2 upgrade (full 255-entry ACI nearest-match) if exact color
    /// fidelity in DXF becomes important; for now the *layer name* also encodes
    /// the human-readable band, so the classification is never ambiguous even
    /// if the on-screen color is an approximation.
    private static func nearestACI(_ color: RGBAColor) -> Int {
        let palette: [(Int, RGBAColor)] = [
            (1, RGBAColor(r: 1, g: 0, b: 0)),      // red
            (2, RGBAColor(r: 1, g: 1, b: 0)),      // yellow
            (3, RGBAColor(r: 0, g: 1, b: 0)),      // green
            (4, RGBAColor(r: 0, g: 1, b: 1)),      // cyan
            (5, RGBAColor(r: 0, g: 0, b: 1)),      // blue
            (6, RGBAColor(r: 1, g: 0, b: 1)),      // magenta
            (7, RGBAColor(r: 1, g: 1, b: 1)),      // white
            (30, RGBAColor(r: 1, g: 0.5, b: 0)),   // orange
            (200, RGBAColor(r: 0.5, g: 0, b: 0.75))// violet/purple
        ]
        var best = palette[0]
        var bestDelta = Double.greatestFiniteMagnitude
        for entry in palette {
            let d = pow(entry.1.r - color.r, 2) + pow(entry.1.g - color.g, 2) + pow(entry.1.b - color.b, 2)
            if d < bestDelta { bestDelta = d; best = entry }
        }
        return best.0
    }
}
