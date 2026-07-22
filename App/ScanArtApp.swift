import SwiftUI
import SwiftData
import ScanArtCore
import ScanArtPersistence
import ScanArtUI

@main
struct ScanArtApp: App {
    private let diContainer: DIContainer?
    private let modelContainer: ModelContainer?
    private let bootstrapErrorMessage: String?

    init() {
        do {
            let stack = try SwiftDataStack()
            let context = stack.mainContext
            self.diContainer = DIContainer(
                projectRepository: SwiftDataProjectRepository(context: context),
                scanRepository: SwiftDataScanRepository(context: context),
                thicknessResultRepository: SwiftDataThicknessResultRepository(context: context),
                reportRepository: SwiftDataReportRepository(context: context)
            )
            self.modelContainer = stack.modelContainer
            self.bootstrapErrorMessage = nil
        } catch {
            self.diContainer = nil
            self.modelContainer = nil
            self.bootstrapErrorMessage = "Couldn't set up local storage: \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let diContainer, let modelContainer {
                    RootView()
                        .environment(\.diContainer, diContainer)
                        .modelContainer(modelContainer)
                } else {
                    StorageFailureView(message: bootstrapErrorMessage ?? "Unknown error")
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Shown only if the local SwiftData store fails to open (e.g. disk
/// corruption) — should be exceedingly rare, but the app should never
/// silently no-op instead of explaining what happened.
private struct StorageFailureView: View {
    let message: String
    var body: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(ScanArtTheme.statusDanger)
            Text("Couldn't Start Scan Art")
                .font(ScanArtTheme.title())
                .foregroundStyle(ScanArtTheme.textPrimary)
            Text(message)
                .font(ScanArtTheme.body())
                .foregroundStyle(ScanArtTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ScanArtTheme.spacingL)
        }
        .scanArtScreenBackground()
    }
}
