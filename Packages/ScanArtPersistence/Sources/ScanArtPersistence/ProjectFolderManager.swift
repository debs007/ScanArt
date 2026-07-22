import Foundation

/// Manages the on-disk folder tree for each project:
///
/// ```
/// Application Support/ScanArt/Projects/<project-uuid>/
///   Meshes/       *.scanmesh, *.worldmap, *_thumb.jpg
///   Thickness/    *_samples.bin  (per-vertex thickness data)
///   Reports/      *.pdf
///   Exports/      *.dxf, *.obj, *.ply, *.stl, *.usdz, *.csv, *.json
///   Images/       user-captured reference photos
/// ```
///
/// `Application Support` (not `Documents`) is deliberate: this is
/// app-managed data, not meant to be user-browsable via the Files app or
/// exposed via iTunes/Finder file sharing — matching the "local, offline,
/// project-lockable" posture from the spec's Security section. Exports are
/// still handed to the user via a share sheet at the point of export (see
/// the app's ExportCoordinator), which is the appropriate, explicit way to
/// get a file out of the sandbox rather than leaving the whole store browsable.
public struct ProjectFolderManager {
    private let fileManager = FileManager.default
    private let rootURL: URL

    public init() throws {
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        rootURL = appSupport.appendingPathComponent("ScanArt/Projects", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func projectFolder(for projectID: UUID) throws -> URL {
        let folder = rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        for sub in ["Meshes", "Thickness", "Reports", "Exports", "Images"] {
            try fileManager.createDirectory(at: folder.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        return folder
    }

    public func meshesFolder(for projectID: UUID) throws -> URL {
        try projectFolder(for: projectID).appendingPathComponent("Meshes", isDirectory: true)
    }

    public func thicknessFolder(for projectID: UUID) throws -> URL {
        try projectFolder(for: projectID).appendingPathComponent("Thickness", isDirectory: true)
    }

    public func reportsFolder(for projectID: UUID) throws -> URL {
        try projectFolder(for: projectID).appendingPathComponent("Reports", isDirectory: true)
    }

    public func exportsFolder(for projectID: UUID) throws -> URL {
        try projectFolder(for: projectID).appendingPathComponent("Exports", isDirectory: true)
    }

    public func imagesFolder(for projectID: UUID) throws -> URL {
        try projectFolder(for: projectID).appendingPathComponent("Images", isDirectory: true)
    }

    public func deleteProjectFolder(for projectID: UUID) throws {
        let folder = rootURL.appendingPathComponent(projectID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }

    /// Storage check ahead of starting a scan (spec: "Storage full" error
    /// case). LiDAR meshes are modest (a room is typically low tens of MB
    /// uncompressed) but this guards against scanning on an already-full device.
    public func availableCapacityMB() -> Double {
        guard let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return .greatestFiniteMagnitude }
        return Double(capacity) / 1_048_576
    }
}
