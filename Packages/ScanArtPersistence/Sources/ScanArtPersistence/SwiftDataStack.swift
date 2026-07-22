import Foundation
import SwiftData
import ScanArtCore

/// Owns the app's single `ModelContainer`. Everything is local — no
/// `CloudKit` configuration, matching the spec's "completely offline, no
/// backend, no cloud" requirement.
@MainActor
public final class SwiftDataStack {
    public let modelContainer: ModelContainer

    public init(inMemoryForTesting: Bool = false) throws {
        let schema = Schema([Project.self, ScanRecord.self, ThicknessResult.self, ReportRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemoryForTesting,
            cloudKitDatabase: .none
        )
        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
    }

    public var mainContext: ModelContext { modelContainer.mainContext }
}
