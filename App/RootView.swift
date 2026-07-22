import SwiftUI
import Foundation
import ScanArtCore

/// Type-safe navigation destinations for the app's single `NavigationStack`.
/// Kept as one enum (rather than per-feature stacks) since the spec's flows
/// cross features constantly (Project -> Scan -> Analysis -> Reports).
enum AppRoute: Hashable {
    case projectList
    case projectDetail(projectID: UUID)
    case scan(projectID: UUID)
    case rescan(projectID: UUID)
    case analysis(projectID: UUID, scanID: UUID)
    case reports(projectID: UUID)
    case settings
    case help
    case about
}

struct RootView: View {
    @State private var isShowingSplash = true
    @State private var path = NavigationPath()
    @State private var isCreatingProject = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path, isCreatingProject: $isCreatingProject)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .sheet(isPresented: $isCreatingProject) {
            CreateProjectView { newProjectID in
                isCreatingProject = false
                path.append(AppRoute.projectDetail(projectID: newProjectID))
            }
        }
        .overlay {
            if isShowingSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.3)) { isShowingSplash = false }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .projectList:
            ProjectListView(path: $path, isCreatingProject: $isCreatingProject)
        case .projectDetail(let projectID):
            ProjectDetailView(projectID: projectID, path: $path)
        case .scan(let projectID):
            ScanView(projectID: projectID, path: $path)
        case .rescan(let projectID):
            RescanView(projectID: projectID, path: $path)
        case .analysis(let projectID, let scanID):
            AnalysisView(projectID: projectID, scanID: scanID)
        case .reports(let projectID):
            ReportListView(projectID: projectID)
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        case .about:
            AboutView()
        }
    }
}
