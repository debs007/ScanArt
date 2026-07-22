import Foundation
import SwiftData
import ScanArtCore

@MainActor
public final class SwiftDataProjectRepository: ProjectRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func fetchAllProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.dateModified, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func fetchProject(id: UUID) throws -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func searchProjects(query: String) throws -> [Project] {
        guard !query.isEmpty else { return try fetchAllProjects() }
        return try fetchAllProjects().filter { $0.matches(searchQuery: query) }
    }

    public func createProject(_ project: Project) throws {
        context.insert(project)
        try context.save()
    }

    public func save() throws {
        try context.save()
    }

    public func deleteProject(_ project: Project) throws {
        context.delete(project)
        try context.save()
    }
}

@MainActor
public final class SwiftDataScanRepository: ScanRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func addScan(_ scan: ScanRecord, to project: Project) throws {
        scan.project = project
        project.scans.append(scan)
        project.dateModified = Date()
        context.insert(scan)
        try context.save()
    }

    public func deleteScan(_ scan: ScanRecord) throws {
        context.delete(scan)
        try context.save()
    }

    public func save() throws { try context.save() }
}

@MainActor
public final class SwiftDataThicknessResultRepository: ThicknessResultRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func addResult(_ result: ThicknessResult, to scan: ScanRecord) throws {
        result.scan = scan
        scan.thicknessResults.append(result)
        scan.dateModified = Date()
        context.insert(result)
        try context.save()
    }

    public func save() throws { try context.save() }
}

@MainActor
public final class SwiftDataReportRepository: ReportRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func addReport(_ report: ReportRecord, to project: Project) throws {
        report.project = project
        project.reports.append(report)
        context.insert(report)
        try context.save()
    }

    public func save() throws { try context.save() }
}
