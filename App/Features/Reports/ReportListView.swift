import SwiftUI
import ScanArtCore
import ScanArtPersistence
import ScanArtUI

struct ReportListView: View {
    let projectID: UUID
    @Environment(\.diContainer) private var di

    @State private var project: Project?
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
                if let reports = project?.reports, !reports.isEmpty {
                    ForEach(reports.sorted { $0.generatedDate > $1.generatedDate }) { report in
                        reportRow(report)
                    }
                } else {
                    emptyState
                }
            }
            .padding(ScanArtTheme.spacingM)
        }
        .scanArtScreenBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onAppear { load() }
        .sheet(item: Binding(get: { shareURL.map(ShareURLItem.init) }, set: { shareURL = $0?.url })) { item in
            ReportShareSheet(url: item.url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(ScanArtTheme.textTertiary)
            Text("No reports yet")
                .font(ScanArtTheme.body(15))
                .foregroundStyle(ScanArtTheme.textSecondary)
            Text("Generate one from the Analysis screen after computing a thickness map.")
                .font(ScanArtTheme.body(12))
                .foregroundStyle(ScanArtTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, ScanArtTheme.spacingXL)
        .frame(maxWidth: .infinity)
    }

    private func reportRow(_ report: ReportRecord) -> some View {
        Button {
            openReport(report)
        } label: {
            HStack(spacing: ScanArtTheme.spacingM) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(ScanArtTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title).font(ScanArtTheme.body(15)).foregroundStyle(ScanArtTheme.textPrimary)
                    Text(DateFormatter.reportListDate.string(from: report.generatedDate))
                        .font(ScanArtTheme.body(12))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(ScanArtTheme.textTertiary)
            }
            .padding(ScanArtTheme.spacingM)
            .background(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM).fill(ScanArtTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
    }

    private func openReport(_ report: ReportRecord) {
        guard let folderManager = try? ProjectFolderManager(),
              let folder = try? folderManager.reportsFolder(for: projectID) else { return }
        shareURL = folder.appendingPathComponent(report.pdfFileName)
    }

    private func load() {
        guard let di else { return }
        do {
            project = try di.projectRepository.fetchProject(id: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShareURLItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ReportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension DateFormatter {
    static let reportListDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
