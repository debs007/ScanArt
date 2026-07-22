import Foundation
import SwiftData

/// A thickness-measurement project: one wall (or set of walls) tracked from
/// its original pre-work scan through any number of rescans.
///
/// Storage split: this model — and SwiftData generally — holds lightweight
/// metadata only, which is what makes "Search project by customer/site/date/
/// engineer" fast. Heavy binary data (mesh geometry, per-vertex thickness
/// samples) lives in flat files under the project's folder on disk, referenced
/// by filename from `ScanRecord` / `ThicknessResult`. See
/// ScanArtPersistence.ProjectFolderManager for the on-disk layout.
///
/// All physical measurements are stored in MILLIMETERS regardless of the
/// project's display `unit` — `unit` only controls formatting in the UI.
@Model
public final class Project {
    @Attribute(.unique) public var id: UUID

    public var name: String
    public var projectDescription: String
    public var location: String
    public var customerName: String
    public var engineerName: String
    public var siteName: String
    public var buildingName: String
    public var roomName: String
    public var floorNumber: String
    public var notes: String

    public var dateCreated: Date
    public var dateModified: Date

    /// Target thickness/depth, millimeters (e.g. 4 cm plaster → 40.0).
    public var desiredThicknessMM: Double
    /// Symmetric tolerance band around the desired thickness, millimeters.
    public var toleranceMM: Double
    public var unitRawValue: String

    /// "plaster" or "excavation" — see `ProjectType`. Stored as raw String so
    /// SwiftData performs a lightweight migration for older rows (defaulting to
    /// "plaster") without requiring a schema version bump.
    public var projectTypeRawValue: String = ProjectType.plaster.rawValue

    public var thumbnailFileName: String?

    /// Reserved for the Face ID / passcode project lock described in the spec's
    /// Security section. Enforcement UI is a Phase 2 item but the flag lives on
    /// the model now so it round-trips through sync/export without a migration.
    public var isLocked: Bool

    @Relationship(deleteRule: .cascade, inverse: \ScanRecord.project)
    public var scans: [ScanRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \ReportRecord.project)
    public var reports: [ReportRecord] = []

    public init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        location: String = "",
        customerName: String = "",
        engineerName: String = "",
        siteName: String = "",
        buildingName: String = "",
        roomName: String = "",
        floorNumber: String = "",
        notes: String = "",
        desiredThicknessMM: Double,
        toleranceMM: Double,
        unit: MeasurementUnit = .centimeters,
        projectType: ProjectType = .plaster
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.location = location
        self.customerName = customerName
        self.engineerName = engineerName
        self.siteName = siteName
        self.buildingName = buildingName
        self.roomName = roomName
        self.floorNumber = floorNumber
        self.notes = notes
        self.dateCreated = Date()
        self.dateModified = Date()
        self.desiredThicknessMM = desiredThicknessMM
        self.toleranceMM = toleranceMM
        self.unitRawValue = unit.rawValue
        self.projectTypeRawValue = projectType.rawValue
        self.thumbnailFileName = nil
        self.isLocked = false
    }

    public var unit: MeasurementUnit {
        get { MeasurementUnit(rawValue: unitRawValue) ?? .centimeters }
        set { unitRawValue = newValue.rawValue }
    }

    public var projectType: ProjectType {
        get { ProjectType(rawValue: projectTypeRawValue) ?? .plaster }
        set { projectTypeRawValue = newValue.rawValue }
    }

    public var originalScan: ScanRecord? {
        scans.first { $0.scanType == .original }
    }

    public var rescans: [ScanRecord] {
        scans.filter { $0.scanType == .rescan }.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    /// Next sequence number to assign to a new rescan.
    public var nextRescanSequenceNumber: Int {
        (rescans.map(\.sequenceNumber).max() ?? 0) + 1
    }

    public func matches(searchQuery query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || customerName.lowercased().contains(q)
            || siteName.lowercased().contains(q)
            || engineerName.lowercased().contains(q)
            || buildingName.lowercased().contains(q)
            || roomName.lowercased().contains(q)
    }
}
