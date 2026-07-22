import Foundation
import SwiftData

/// The output of comparing two scans (spec: "Compare any scans — Original vs
/// Scan 1, Scan 3 vs Scan 9, etc."). Aggregate statistics are stored directly
/// as SwiftData attributes for fast list/report display; the full per-vertex
/// sample array lives in a companion binary file (see ScanArtPersistence).
///
/// One `ScanRecord` can have multiple `ThicknessResult`s if the user compares
/// it against different baselines.
@Model
public final class ThicknessResult {
    @Attribute(.unique) public var id: UUID
    public var scan: ScanRecord?

    /// The OTHER scan this comparison was measured against (usually the
    /// original, but the spec explicitly allows any pair).
    public var comparedAgainstScanID: UUID

    /// Filename (relative to the project's Thickness/ folder) of the binary
    /// per-sample data (position + normal + thickness, see MeshFileStorage).
    public var samplesFileName: String

    public var dateComputed: Date
    public var methodRawValue: String // "nearestNeighborProjection" | "rayMeshIntersection"

    public var sampleCount: Int
    public var validSampleCount: Int
    public var averageMM: Double
    public var minimumMM: Double
    public var maximumMM: Double
    public var medianMM: Double
    public var standardDeviationMM: Double
    public var withinTolerancePercent: Double
    public var outOfTolerancePercent: Double
    public var volumeCubicMeters: Double

    public init(
        id: UUID = UUID(),
        comparedAgainstScanID: UUID,
        samplesFileName: String,
        method: String,
        sampleCount: Int,
        validSampleCount: Int,
        averageMM: Double,
        minimumMM: Double,
        maximumMM: Double,
        medianMM: Double,
        standardDeviationMM: Double,
        withinTolerancePercent: Double,
        outOfTolerancePercent: Double,
        volumeCubicMeters: Double
    ) {
        self.id = id
        self.comparedAgainstScanID = comparedAgainstScanID
        self.samplesFileName = samplesFileName
        self.dateComputed = Date()
        self.methodRawValue = method
        self.sampleCount = sampleCount
        self.validSampleCount = validSampleCount
        self.averageMM = averageMM
        self.minimumMM = minimumMM
        self.maximumMM = maximumMM
        self.medianMM = medianMM
        self.standardDeviationMM = standardDeviationMM
        self.withinTolerancePercent = withinTolerancePercent
        self.outOfTolerancePercent = outOfTolerancePercent
        self.volumeCubicMeters = volumeCubicMeters
    }

    public var coveragePercent: Double {
        sampleCount == 0 ? 0 : Double(validSampleCount) / Double(sampleCount) * 100
    }
}
