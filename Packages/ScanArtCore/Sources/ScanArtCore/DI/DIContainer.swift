import SwiftUI

/// Composition root. Built once in `ScanArtApp` and threaded through the view
/// hierarchy via the SwiftUI environment rather than singletons, so view
/// models can be given fakes/mocks in previews and tests.
@MainActor
public final class DIContainer: ObservableObject {
    public let projectRepository: ProjectRepository
    public let scanRepository: ScanRepository
    public let thicknessResultRepository: ThicknessResultRepository
    public let reportRepository: ReportRepository

    public init(
        projectRepository: ProjectRepository,
        scanRepository: ScanRepository,
        thicknessResultRepository: ThicknessResultRepository,
        reportRepository: ReportRepository
    ) {
        self.projectRepository = projectRepository
        self.scanRepository = scanRepository
        self.thicknessResultRepository = thicknessResultRepository
        self.reportRepository = reportRepository
    }
}

private struct DIContainerKey: EnvironmentKey {
    static let defaultValue: DIContainer? = nil
}

public extension EnvironmentValues {
    var diContainer: DIContainer? {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }
}
