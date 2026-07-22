import Foundation
import SwiftData

/// Metadata for a single LiDAR scan (the original pre-plaster capture, or one
/// of unlimited rescans). The actual mesh geometry is NOT stored here — it
/// lives in a `.scanmesh` binary file on disk (see ScanArtPersistence.
/// MeshFileStorage); this row is what makes the project timeline and search
/// fast without loading multi-megabyte mesh data.
@Model
public final class ScanRecord {
    @Attribute(.unique) public var id: UUID
    public var project: Project?

    public var scanTypeRawValue: String
    /// 0 for the original scan; 1, 2, 3... for rescans in capture order.
    public var sequenceNumber: Int
    /// User-editable label, e.g. "Rescan 3" or "After second coat".
    public var label: String

    public var dateCreated: Date
    public var dateModified: Date

    /// Filename (relative to the project's Meshes/ folder) of the compressed
    /// mesh binary.
    public var meshFileName: String
    /// Filename of the archived ARWorldMap captured alongside this scan, if
    /// any — used for relocalization-based alignment on the NEXT rescan.
    public var worldMapFileName: String?
    public var thumbnailFileName: String?

    public var vertexCount: Int
    public var faceCount: Int
    public var surfaceAreaSquareMeters: Double

    public var boundingBoxMinX: Double
    public var boundingBoxMinY: Double
    public var boundingBoxMinZ: Double
    public var boundingBoxMaxX: Double
    public var boundingBoxMaxY: Double
    public var boundingBoxMaxZ: Double

    public var fileSizeBytes: Int64
    public var isCompressed: Bool

    /// Flattened 4x4 rigid alignment transform relative to the original scan.
    /// Nil for the original scan itself (which defines the coordinate frame).
    public var alignmentTransform: [Double]?
    /// RMS alignment error in millimeters, surfaced to the user as alignment
    /// quality. Nil for the original scan.
    public var alignmentRMSEMM: Double?
    public var relocalizationSucceeded: Bool?

    public var coveragePercent: Double
    public var scanQualityRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \ThicknessResult.scan)
    public var thicknessResults: [ThicknessResult] = []

    public init(
        id: UUID = UUID(),
        scanType: ScanType,
        sequenceNumber: Int,
        label: String,
        meshFileName: String,
        worldMapFileName: String? = nil,
        thumbnailFileName: String? = nil,
        vertexCount: Int,
        faceCount: Int,
        surfaceAreaSquareMeters: Double,
        boundingBoxMin: (Double, Double, Double),
        boundingBoxMax: (Double, Double, Double),
        fileSizeBytes: Int64,
        isCompressed: Bool,
        alignmentTransform: [Double]? = nil,
        alignmentRMSEMM: Double? = nil,
        relocalizationSucceeded: Bool? = nil,
        coveragePercent: Double,
        scanQuality: ScanQuality
    ) {
        self.id = id
        self.scanTypeRawValue = scanType.rawValue
        self.sequenceNumber = sequenceNumber
        self.label = label
        self.dateCreated = Date()
        self.dateModified = Date()
        self.meshFileName = meshFileName
        self.worldMapFileName = worldMapFileName
        self.thumbnailFileName = thumbnailFileName
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.surfaceAreaSquareMeters = surfaceAreaSquareMeters
        self.boundingBoxMinX = boundingBoxMin.0
        self.boundingBoxMinY = boundingBoxMin.1
        self.boundingBoxMinZ = boundingBoxMin.2
        self.boundingBoxMaxX = boundingBoxMax.0
        self.boundingBoxMaxY = boundingBoxMax.1
        self.boundingBoxMaxZ = boundingBoxMax.2
        self.fileSizeBytes = fileSizeBytes
        self.isCompressed = isCompressed
        self.alignmentTransform = alignmentTransform
        self.alignmentRMSEMM = alignmentRMSEMM
        self.relocalizationSucceeded = relocalizationSucceeded
        self.coveragePercent = coveragePercent
        self.scanQualityRawValue = scanQuality.rawValue
    }

    public var scanType: ScanType {
        get { ScanType(rawValue: scanTypeRawValue) ?? .rescan }
        set { scanTypeRawValue = newValue.rawValue }
    }

    public var scanQuality: ScanQuality {
        get { ScanQuality(rawValue: scanQualityRawValue) ?? .fair }
        set { scanQualityRawValue = newValue.rawValue }
    }

    public var displayName: String {
        label.isEmpty ? (scanType == .original ? "Original Scan" : "Rescan \(sequenceNumber)") : label
    }
}
