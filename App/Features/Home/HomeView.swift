import SwiftUI
import ScanArtCore
import ScanArtUI

struct HomeView: View {
    @Binding var path: NavigationPath
    @Binding var isCreatingProject: Bool
    @Environment(\.diContainer) private var di

    @State private var recentProjects: [Project] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingL) {
                actionButtons
                if !recentProjects.isEmpty {
                    recentSection
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, ScanArtTheme.spacingL)
            .padding(.top, ScanArtTheme.spacingM)
            .padding(.bottom, ScanArtTheme.spacingXL)
        }
        .scanArtScreenBackground()
        .navigationTitle("Scan Art")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Settings", systemImage: "gearshape") { path.append(AppRoute.settings) }
                    Button("Help", systemImage: "questionmark.circle") { path.append(AppRoute.help) }
                    Button("About", systemImage: "info.circle") { path.append(AppRoute.about) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(ScanArtTheme.textPrimary)
                }
            }
        }
        .task { loadRecentProjects() }
        .onAppear { loadRecentProjects() }
    }

    private var actionButtons: some View {
        VStack(spacing: ScanArtTheme.spacingS) {
            PrimaryButton("New Project", systemImage: "plus.circle.fill") {
                isCreatingProject = true
            }
            SecondaryButton("All Projects", systemImage: "square.grid.2x2") {
                path.append(AppRoute.projectList)
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: ScanArtTheme.spacingM) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                    .padding(.top, ScanArtTheme.spacingS)
                Text("No projects yet")
                    .font(ScanArtTheme.title(18))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                Text("Tap New Project to start measuring\nplaster thickness with LiDAR.")
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, ScanArtTheme.spacingS)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
            Text("RECENT PROJECTS")
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.textTertiary)
                .padding(.top, ScanArtTheme.spacingXS)
            ForEach(recentProjects.prefix(5)) { project in
                Button {
                    path.append(AppRoute.projectDetail(projectID: project.id))
                } label: {
                    ProjectRow(project: project)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadRecentProjects() {
        guard let di else { return }
        do {
            recentProjects = try di.projectRepository.fetchAllProjects()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: ScanArtTheme.spacingM) {
            ZStack {
                RoundedRectangle(cornerRadius: ScanArtTheme.radiusS)
                    .fill(ScanArtTheme.accentMuted)
                    .frame(width: 48, height: 48)
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(ScanArtTheme.accent)
                    .font(.system(size: 20, weight: .light))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(ScanArtTheme.body(16))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                let location = [project.siteName, project.roomName]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !location.isEmpty {
                    Text(location)
                        .font(ScanArtTheme.body(12))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(project.rescans.count)")
                    .font(ScanArtTheme.monospacedValue(14))
                    .foregroundStyle(ScanArtTheme.textTertiary)
                Text("scans")
                    .font(ScanArtTheme.label(10))
                    .foregroundStyle(ScanArtTheme.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ScanArtTheme.textTertiary)
        }
        .padding(ScanArtTheme.spacingM)
        .background(
            RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                .fill(ScanArtTheme.surfaceElevated)
        )
    }
}
