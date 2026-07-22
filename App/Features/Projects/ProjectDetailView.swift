import SwiftUI
import ScanArtCore
import ScanArtUI

struct ProjectDetailView: View {
    let projectID: UUID
    @Binding var path: NavigationPath
    @Environment(\.diContainer) private var di

    @State private var project: Project?
    @State private var errorMessage: String?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            if let project {
                VStack(alignment: .leading, spacing: ScanArtTheme.spacingL) {
                    summaryCard(for: project)

                    if project.originalScan == nil {
                        PrimaryButton("Start Original Scan", systemImage: "camera.metering.matrix") {
                            path.append(AppRoute.scan(projectID: project.id))
                        }
                    } else {
                        PrimaryButton("New Rescan", systemImage: "arrow.triangle.2.circlepath.camera") {
                            path.append(AppRoute.rescan(projectID: project.id))
                        }
                        SecondaryButton("Reports", systemImage: "doc.text") {
                            path.append(AppRoute.reports(projectID: project.id))
                        }
                    }

                    timeline(for: project)
                }
                .padding(ScanArtTheme.spacingL)
            } else {
                ProgressView().padding(.top, ScanArtTheme.spacingXL)
            }
        }
        .scanArtScreenBackground()
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete this project? This removes all scans and reports.", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) { deleteProject() }
            Button("Cancel", role: .cancel) {}
        }
        .task { load() }
        .onAppear { load() }
    }

    private func summaryCard(for project: Project) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
                HStack {
                    StatCard(label: "Desired", value: project.unit.format(mm: project.desiredThicknessMM))
                    StatCard(label: "Tolerance", value: "± " + project.unit.format(mm: project.toleranceMM))
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
            Text("TIMELINE").font(ScanArtTheme.label()).foregroundStyle(ScanArtTheme.textTertiary)

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
                    Text("\(scan.vertexCount) vertices · \(Int(scan.coveragePercent))% coverage")
                        .font(ScanArtTheme.body(12))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
                Spacer()
                if !scan.thicknessResults.isEmpty {
                    Image(systemName: "chart.bar.fill").foregroundStyle(ScanArtTheme.accent)
                } else if scan.scanType == .rescan {
                    Text("Tap to analyze").font(ScanArtTheme.body(11)).foregroundStyle(ScanArtTheme.textTertiary)
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
