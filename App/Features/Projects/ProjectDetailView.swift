import SwiftUI
import ScanArtCore
import ScanArtUI

struct ProjectDetailView: View {
    let projectID: UUID
    @Binding var path: NavigationPath
    @Environment(\.diContainer) private var di
    @Environment(LocalizationManager.self) private var l10n

    @State private var project: Project?
    @State private var errorMessage: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var isEditingColors = false
    @State private var isEditingProject = false

    var body: some View {
        ScrollView {
            if let project {
                VStack(alignment: .leading, spacing: ScanArtTheme.spacingL) {
                    summaryCard(for: project)

                    if project.originalScan == nil {
                        PrimaryButton(l10n("detail.startOriginalScan"), systemImage: "camera.metering.matrix") {
                            path.append(AppRoute.scan(projectID: project.id))
                        }
                    } else {
                        PrimaryButton(l10n("detail.newRescan"), systemImage: "arrow.triangle.2.circlepath.camera") {
                            path.append(AppRoute.rescan(projectID: project.id))
                        }
                        SecondaryButton(l10n("detail.reports"), systemImage: "doc.text") {
                            path.append(AppRoute.reports(projectID: project.id))
                        }
                    }

                    colorPaletteButton(for: project)

                    timeline(for: project)
                }
                .padding(ScanArtTheme.spacingL)
            } else {
                ProgressView().padding(.top, ScanArtTheme.spacingXL)
            }
        }
        .scanArtScreenBackground()
        .navigationTitle(project?.name ?? l10n("project.section"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isEditingProject = true } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(l10n("project.deleteConfirm"), isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button(l10n("project.deleteTitle"), role: .destructive) { deleteProject() }
            Button(l10n("action.cancel"), role: .cancel) {}
        }
        .task { load() }
        .onAppear { load() }
        .sheet(isPresented: $isEditingColors) {
            if let project { ColorPaletteEditorView(project: project) }
        }
        .sheet(isPresented: $isEditingProject) {
            if let project { EditProjectView(project: project, onSaved: { load() }) }
        }
    }

    private func colorPaletteButton(for project: Project) -> some View {
        Button {
            isEditingColors = true
        } label: {
            HStack(spacing: ScanArtTheme.spacingM) {
                let stops = project.colorMapper().stops
                LinearGradient(
                    colors: stops.map { Color(red: $0.color.r, green: $0.color.g, blue: $0.color.b) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 36, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text(l10n("detail.colorPalette"))
                    .font(ScanArtTheme.body(16))
                    .foregroundStyle(ScanArtTheme.textPrimary)

                Spacer()

                if project.hasCustomColors {
                    Text(l10n("detail.colorPalette.custom"))
                        .font(ScanArtTheme.label())
                        .foregroundStyle(ScanArtTheme.accent)
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
        .buttonStyle(.plain)
    }

    private func summaryCard(for project: Project) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
                HStack {
                    StatCard(label: l10n("detail.desired"), value: project.unit.format(mm: project.desiredThicknessMM))
                    StatCard(label: l10n("detail.tolerance"), value: "± " + project.unit.format(mm: project.toleranceMM))
                }
                if !project.customerName.isEmpty {
                    Label(project.customerName, systemImage: "person.fill").font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textSecondary)
                }
                let location = [project.siteName, project.buildingName, project.roomName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !location.isEmpty {
                    Label(location, systemImage: "location.fill").font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textSecondary)
                }
            }
        }
    }

    private func timeline(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
            Text(l10n("detail.timeline")).font(ScanArtTheme.label()).foregroundStyle(ScanArtTheme.textTertiary)

            if let original = project.originalScan {
                scanCard(original, project: project)
            }
            ForEach(project.rescans) { rescan in
                scanCard(rescan, project: project)
            }
        }
    }

    private func scanCard(_ scan: ScanRecord, project: Project) -> some View {
        Button {
            if scan.scanType == .rescan {
                path.append(AppRoute.analysis(projectID: project.id, scanID: scan.id))
            }
        } label: {
            HStack(spacing: ScanArtTheme.spacingM) {
                Circle()
                    .fill(qualityColor(scan.scanQuality))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.displayName).font(ScanArtTheme.body(15)).foregroundStyle(ScanArtTheme.textPrimary)
                    Text("\(scan.vertexCount) \(l10n("detail.vertices")) · \(Int(scan.coveragePercent))% \(l10n("detail.coverage"))")
                        .font(ScanArtTheme.body(12))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
                Spacer()
                if !scan.thicknessResults.isEmpty {
                    Image(systemName: "chart.bar.fill").foregroundStyle(ScanArtTheme.accent)
                } else if scan.scanType == .rescan {
                    Text(l10n("detail.tapToAnalyze")).font(ScanArtTheme.body(11)).foregroundStyle(ScanArtTheme.textTertiary)
                }
            }
            .padding(ScanArtTheme.spacingM)
            .background(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM).fill(ScanArtTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
        .disabled(scan.scanType == .original)
    }

    private func qualityColor(_ quality: ScanQuality) -> Color {
        switch quality {
        case .poor: return ScanArtTheme.statusDanger
        case .fair: return ScanArtTheme.statusWarning
        case .good: return ScanArtTheme.statusInfo
        case .excellent: return ScanArtTheme.statusGood
        }
    }

    private func load() {
        guard let di else { return }
        do {
            project = try di.projectRepository.fetchProject(id: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProject() {
        guard let di, let project else { return }
        do {
            try di.projectRepository.deleteProject(project)
            path.removeLast(path.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
