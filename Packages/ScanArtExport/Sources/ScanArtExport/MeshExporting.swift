import Foundation
import ScanArtAlgorithms

public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
    case dxf, obj, ply, stl, usdz, csv, json, pdf

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .dxf: return "DXF (AutoCAD / Civil3D / Revit / BricsCAD)"
        case .obj: return "OBJ (Wavefront)"
        case .ply: return "PLY (colored point/mesh)"
        case .stl: return "STL (3D printing / CAD)"
        case .usdz: return "USDZ (AR Quick Look)"
        case .csv: return "CSV (raw sample points)"
        case .json: return "JSON (full data dump)"
        case .pdf: return "PDF (report)"
        }
    }
}

/// Everything an exporter might need. Not every exporter uses every field —
/// e.g. STL ignores `samples`/`colorMapper` since the format carries no color.
public struct ExportPayload: Sendable {
    public let mesh: MeshBuffer
    public let samples: [ThicknessSample]?
    public let colorMapper: ThicknessColorMapper?
    public let projectName: String
    public let scanLabel: String

    public init(mesh: MeshBuffer, samples: [ThicknessSample]? = nil, colorMapper: ThicknessColorMapper? = nil, projectName: String, scanLabel: String) {
        self.mesh = mesh
        self.samples = samples
        self.colorMapper = colorMapper
        self.projectName = projectName
        self.scanLabel = scanLabel
    }
}

public protocol MeshExporter {
    static func export(_ payload: ExportPayload, to url: URL) throws
}
