import Foundation
import ScanArtAlgorithms

/// Every sampled point: X, Y, Z, Thickness, Color — exactly the fields the
/// spec's CSV Export section lists.
public enum CSVExporter: MeshExporter {
    public static func export(_ payload: ExportPayload, to url: URL) throws {
        guard let samples = payload.samples else {
            throw ExportError.missingData("CSV export requires computed thickness samples")
        }
        let colorMapper = payload.colorMapper ?? .standard(desiredThicknessMM: 40, toleranceMM: 2)

        var csv = "X,Y,Z,Thickness_mm,Color\n"
        csv.reserveCapacity(samples.count * 40)
        for sample in samples {
            let color = sample.isValid ? colorMapper.color(for: Double(sample.thicknessMM)) : ThicknessColorMapper.noData
            csv += "\(sample.position.x),\(sample.position.y),\(sample.position.z),"
            csv += sample.isValid ? "\(sample.thicknessMM)" : ""
            csv += ",\(color.hexString)\n"
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Full structured dump — geometry, samples, and statistics — for
/// interoperability with external tooling or debugging.
public enum JSONExporter: MeshExporter {
    private struct Payload: Codable {
        struct Vertex: Codable { let x: Float, y: Float, z: Float }
        struct Sample: Codable { let x: Float, y: Float, z: Float, thicknessMM: Float?, valid: Bool }
        let projectName: String
        let scanLabel: String
        let vertexCount: Int
        let faceCount: Int
        let samples: [Sample]?
    }

    public static func export(_ payload: ExportPayload, to url: URL) throws {
        let samples = payload.samples?.map {
            Payload.Sample(x: $0.position.x, y: $0.position.y, z: $0.position.z, thicknessMM: $0.isValid ? $0.thicknessMM : nil, valid: $0.isValid)
        }
        let body = Payload(
            projectName: payload.projectName,
            scanLabel: payload.scanLabel,
            vertexCount: payload.mesh.vertexCount,
            faceCount: payload.mesh.faceCount,
            samples: samples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(body)
        try data.write(to: url, options: .atomic)
    }
}

public enum ExportError: Error, LocalizedError {
    case missingData(String)
    public var errorDescription: String? {
        switch self { case .missingData(let msg): return msg }
    }
}
