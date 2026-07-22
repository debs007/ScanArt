import SwiftUI
import Combine
import ScanArtRendering
import ScanArtExport
import ScanArtCore
import ScanArtUI

struct AnalysisView: View {
    let projectID: UUID
    let scanID: UUID
    @Environment(\.diContainer) private var di

    @StateObject private var viewModel: AnalysisViewModelBox
    @State private var isShowingExportMenu = false
    @State private var isShowingStatsSheet = false
    @State private var shareURL: URL?

    init(projectID: UUID, scanID: UUID) {
        self.projectID = projectID
        self.scanID = scanID
        self._viewModel = StateObject(wrappedValue: AnalysisViewModelBox())
    }

    var body: some View {
        ZStack {
            ScanArtTheme.backgroundPrimary.ignoresSafeArea()

            if let vm = viewModel.vm {
                MetalMeshView(controller: vm.meshViewController)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    bottomPanel(vm: vm)
                }
                .padding(ScanArtTheme.spacingM)

                if !vm.hasResult {
                    generatePrompt(vm: vm)
                }

                if let error = vm.errorMessage {
                    errorToast(error) { vm.errorMessage = nil }
                }
            } else {
                ProgressView().tint(ScanArtTheme.accent)
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm = viewModel.vm, vm.hasResult {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(ExportFormat.allCases.filter { $0 != .pdf }) { format in
                            Button(format.displayName) { Task { await vm.export(format: format) } }
                        }
                        Button("Generate PDF Report") { Task { await vm.generateReport() } }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if viewModel.vm == nil, let di {
                viewModel.vm = AnalysisViewModel(projectID: projectID, scanID: scanID, di: di)
                Task { await viewModel.vm?.load() }
            }
        }
        .onChange(of: viewModel.vm?.lastExportURL) { _, newValue in
            if let newValue { shareURL = newValue }
        }
        .onChange(of: viewModel.vm?.lastReportURL) { _, newValue in
            if let newValue { shareURL = newValue }
        }
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(url: item.url)
        }
    }

    @ViewBuilder
    private func generatePrompt(vm: AnalysisViewModel) -> some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 36))
                .foregroundStyle(ScanArtTheme.accent)
            Text("Thickness map not generated yet")
                .font(ScanArtTheme.title(17))
                .foregroundStyle(ScanArtTheme.textPrimary)
            Text("Compares this rescan against the project's original scan to compute \(vm.project?.projectType.measurementDescription ?? "thickness").")
                .font(ScanArtTheme.body(13))
                .foregroundStyle(ScanArtTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ScanArtTheme.spacingL)

            if vm.isGenerating {
                ProgressView("Computing…").tint(ScanArtTheme.accent)
            } else {
                PrimaryButton("Generate Thickness Map", systemImage: "wand.and.rays") {
                    Task { await vm.generateThicknessMap() }
                }
                .padding(.horizontal, ScanArtTheme.spacingXL)
            }
        }
        .padding(ScanArtTheme.spacingL)
        .glassPanel()
        .padding(ScanArtTheme.spacingL)
    }

    @ViewBuilder
    private func bottomPanel(vm: AnalysisViewModel) -> some View {
        if vm.hasResult {
            VStack(spacing: ScanArtTheme.spacingS) {
                HStack(spacing: ScanArtTheme.spacingS) {
                    StatCard(label: "Average", value: (vm.project?.unit ?? .centimeters).format(mm: vm.statistics.averageMM))
                    StatCard(label: "In Tolerance", value: String(format: "%.0f%%", vm.statistics.withinTolerancePercent), tint: toleranceColor(vm.statistics.withinTolerancePercent))
                }
                HStack(spacing: ScanArtTheme.spacingS) {
                    StatCard(label: "Min", value: (vm.project?.unit ?? .centimeters).format(mm: vm.statistics.minimumMM))
                    StatCard(label: "Max", value: (vm.project?.unit ?? .centimeters).format(mm: vm.statistics.maximumMM))
                }
                Button {
                    isShowingStatsSheet = true
                } label: {
                    Label("Full Statistics", systemImage: "chart.bar.doc.horizontal")
                        .font(ScanArtTheme.body(13))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
                .padding(.top, 2)
            }
            .sheet(isPresented: $isShowingStatsSheet) {
                StatisticsSheet(vm: vm)
            }
        }
    }

    private func toleranceColor(_ percent: Double) -> Color {
        switch percent {
        case 80...: return ScanArtTheme.statusGood
        case 50..<80: return ScanArtTheme.statusWarning
        default: return ScanArtTheme.statusDanger
        }
    }

    private func errorToast(_ message: String, dismiss: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(ScanArtTheme.body(13))
                .foregroundStyle(.white)
                .padding(ScanArtTheme.spacingM)
                .background(ScanArtTheme.statusDanger, in: RoundedRectangle(cornerRadius: ScanArtTheme.radiusM))
                .onTapGesture(perform: dismiss)
                .padding(.bottom, 260)
        }
    }
}

private struct StatisticsSheet: View {
    @ObservedObject var vm: AnalysisViewModel

    var body: some View {
        NavigationStack {
            List {
                Section(vm.project?.projectType.thicknessLabel ?? "Thickness") {
                    statRow("Average", vm.statistics.averageMM)
                    statRow("Median", vm.statistics.medianMM)
                    statRow("Minimum", vm.statistics.minimumMM)
                    statRow("Maximum", vm.statistics.maximumMM)
                    statRow("Std. Deviation", vm.statistics.standardDeviationMM)
                }
                Section("Coverage & Tolerance") {
                    LabeledContent("Coverage", value: String(format: "%.1f%%", vm.statistics.coveragePercent))
                    LabeledContent("Within Tolerance", value: String(format: "%.1f%%", vm.statistics.withinTolerancePercent))
                    LabeledContent("Out of Tolerance", value: String(format: "%.1f%%", vm.statistics.outOfTolerancePercent))
                }
                Section("Volume") {
                    LabeledContent(vm.project?.projectType.volumeLabel ?? "Volume", value: String(format: "%.4f m³", vm.volumeCubicMeters))
                    LabeledContent("Liters", value: String(format: "%.1f L", vm.volumeCubicMeters * 1000))
                }
                if let scan = vm.scan {
                    Section("Scan") {
                        LabeledContent("Surface Area", value: String(format: "%.2f m²", scan.surfaceAreaSquareMeters))
                        LabeledContent("Vertices", value: "\(scan.vertexCount)")
                        if let rmse = scan.alignmentRMSEMM {
                            LabeledContent("Alignment RMSE", value: String(format: "%.2f mm", rmse))
                        }
                    }
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statRow(_ label: String, _ mm: Double) -> some View {
        LabeledContent(label, value: (vm.project?.unit ?? .centimeters).format(mm: mm, decimals: 2))
    }
}

/// See `ScanViewModelBox` in ScanView.swift for why this forwarding is necessary.
@MainActor
final class AnalysisViewModelBox: ObservableObject {
    @Published var vm: AnalysisViewModel? {
        didSet { resubscribe() }
    }
    private var cancellable: AnyCancellable?

    private func resubscribe() {
        cancellable = vm?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
