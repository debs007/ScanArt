import Foundation

/// Repository protocols are deliberately `@MainActor`-bound rather than
/// `Sendable`: SwiftData's `@Model` classes are not safe to pass across actor
/// boundaries (similar to Core Data's `NSManagedObject`), so this app keeps
/// its `ModelContext` on the main actor and does persistence there.
///
/// Heavy computation (ICP, thickness, decimation) deliberately lives in
/// `ScanArtAlgorithms`, which touches no SwiftData types and is free to run
/// on background tasks. ViewModels call into Algorithms off the main actor,
/// then hop back to the main actor to persist results through these
/// repositories. This keeps the concurrency story simple and correct rather
/// than fighting Sendable checking on model objects for marginal benefit.
@MainActor
public protocol ProjectRepository {
    func fetchAllProjects() throws -> [Project]
    func fetchProject(id: UUID) throws -> Project?
    func searchProjects(query: String) throws -> [Project]
    func createProject(_ project: Project) throws
    func save() throws
    func deleteProject(_ project: Project) throws
}

@MainActor
public protocol ScanRepository {
    func addScan(_ scan: ScanRecord, to project: Project) throws
    func deleteScan(_ scan: ScanRecord) throws
    func save() throws
}

@MainActor
public protocol ThicknessResultRepository {
    func addResult(_ result: ThicknessResult, to scan: ScanRecord) throws
    func save() throws
}

@MainActor
public protocol ReportRepository {
    func addReport(_ report: ReportRecord, to project: Project) throws
    func save() throws
}
