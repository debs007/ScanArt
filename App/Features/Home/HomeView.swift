import SwiftUI
import ScanArtCore
import ScanArtUI

struct HomeView: View {
    @Binding var path: NavigationPath
    @Binding var isCreatingProject: Bool
    @Environment(\.diContainer) private var di
    @Environment(LocalizationManager.self) private var l10n

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
        .navigationTitle(l10n("app.name"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(l10n("nav.settings"), systemImage: "gearshape") { path.append(AppRoute.settings) }
                    Button(l10n("nav.help"), systemImage: "questionmark.circle") { path.append(AppRoute.help) }
                    Button(l10n("nav.about"), systemImage: "info.circle") { path.append(AppRoute.about) }
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
            PrimaryButton(l10n("home.newProject"), systemImage: "plus.circle.fill") {
                isCreatingProject = true
            }
            SecondaryButton(l10n("home.allProjects"), systemImage: "square.grid.2x2") {
                path.append(AppRoute.projectList)
            }
            SecondaryButton(l10n("nav.remoteControl"), systemImage: "display.2") {
                path.append(AppRoute.remoteControl)
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
                Text(l10n("home.noProjectsYet"))
                    .font(ScanArtTheme.title(18))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                Text(l10n("home.noProjectsSubtitle"))
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
            Text(l10n("home.recentProjects"))
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.textTertiary)
                .padding(.top, ScanArtTheme.spacingXS)
            ForEach(recentProjects.prefix(5)) { project in
                Button {
                    path.append(AppRoute.projectDetail(projectID: project.id))
                } label: {
                    ProjectRow(project: project, thumbnailURL: thumbnailURL(for: project), scansLabel: l10n("home.scans"))
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

    // MARK: - Thumbnail helpers

    func thumbnailURL(for project: Project) -> URL? {
        guard let filename = project.thumbnailFileName else { return nil }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false) else { return nil }
        return appSupport.appendingPathComponent("ScanArt/Projects/\(project.id.uuidString)/Images/\(filename)")
    }
}

struct ProjectRow: View {
    let project: Project
    var thumbnailURL: URL? = nil
    var scansLabel: String = "scans"

    var body: some View {
        HStack(spacing: ScanArtTheme.spacingM) {
            thumbnailView
                .frame(width: 52, height: 52)
                .background(ScanArtTheme.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: ScanArtTheme.radiusS))

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
                Text(project.dateCreated, style: .date)
                    .font(ScanArtTheme.label(10))
                    .foregroundStyle(ScanArtTheme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(project.rescans.count)")
                    .font(ScanArtTheme.monospacedValue(14))
                    .foregroundStyle(ScanArtTheme.textTertiary)
                Text(scansLabel)
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

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = thumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    defaultIcon
                }
            }
            // Force new AsyncImage when thumbnail is replaced
            .id(project.dateModified)
        } else {
            defaultIcon
        }
    }

    private var defaultIcon: some View {
        Image(systemName: "square.stack.3d.up")
            .foregroundStyle(ScanArtTheme.accent)
            .font(.system(size: 20, weight: .light))
    }
}
