import SwiftUI
import ARKit
import Combine
import ScanArtAR
import ScanArtUI
import ScanArtCore
import ScanArtAlgorithms

struct RescanView: View {
    let projectID: UUID
    @Binding var path: NavigationPath
    @Environment(\.diContainer) private var di
    @Environment(LocalizationManager.self) private var l10n

    @StateObject private var viewModel = RescanViewModelBox()
    @State private var isShowingFinishSheet = false
    @State private var scanLabel = ""
    @State private var showUI = true

    var body: some View {
        ZStack {
            if let vm = viewModel.vm {
                ARCameraView(
                    sessionManager: vm.sessionManager,
                    mode: vm.originalMesh.map {
                        .rescan(
                            originalMesh: $0,
                            alignmentTransform: vm.alignmentTransform,
                            targetThicknessMM: vm.targetThicknessMM,
                            toleranceMM: vm.toleranceMM
                        )
                    } ?? .original,
                    heatmapRequested: vm.heatmapRequested,
                    resetTrigger: vm.resetTrigger,
                    measurementUnit: vm.measurementUnit,
                    projectType: vm.projectType
                )
                .ignoresSafeArea()

                VStack {
                    topBar(vm: vm)
                    Spacer()
                    if showUI {
                        bottomBar(vm: vm)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(ScanArtTheme.spacingM)
                .animation(.easeInOut(duration: 0.2), value: showUI)

                if let error = vm.errorMessage {
                    errorToast(error)
                }
            } else {
                ScanArtTheme.backgroundPrimary.ignoresSafeArea()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if viewModel.vm == nil, let di {
                viewModel.vm = RescanViewModel(projectID: projectID, di: di)
                viewModel.vm?.start()
            }
        }
        .onDisappear { viewModel.vm?.stop() }
        .sheet(isPresented: $isShowingFinishSheet) {
            finishSheet
        }
        .onChange(of: viewModel.vm?.didSave) { _, didSave in
            guard didSave == true, let scanID = viewModel.vm?.savedScanID else { return }
            path.removeLast()
            path.append(AppRoute.analysis(projectID: projectID, scanID: scanID))
        }
    }

    @ViewBuilder
    private func topBar(vm: RescanViewModel) -> some View {
        HStack {
            Button {
                path.removeLast()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(ScanArtTheme.textPrimary)
                    .padding(ScanArtTheme.spacingS)
                    .glassPanel(cornerRadius: ScanArtTheme.radiusS)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() }
            } label: {
                Image(systemName: showUI ? "eye.slash" : "eye")
                    .foregroundStyle(ScanArtTheme.textPrimary)
                    .padding(ScanArtTheme.spacingS)
                    .glassPanel(cornerRadius: ScanArtTheme.radiusS)
            }
            CoverageRing(percent: vm.sessionManager.estimatedCoveragePercent)
        }
    }

    @ViewBuilder
    private func bottomBar(vm: RescanViewModel) -> some View {
        VStack(spacing: ScanArtTheme.spacingS) {
            if vm.heatmapGenerated {
                ThicknessColorLegend(
                    targetMM: Double(vm.targetThicknessMM),
                    toleranceMM: Double(vm.toleranceMM),
                    unit: vm.measurementUnit
                )
            }

            TabView {
                // Page 1 — scan progress
                HStack(spacing: ScanArtTheme.spacingS) {
                    StatCard(
                        label: l10n("scan.mesh"),
                        value: "\(vm.sessionManager.meshAnchorCount)",
                        unit: l10n("scan.anchors")
                    )
                    StatCard(
                        label: l10n("scan.coverage"),
                        value: "\(Int(vm.sessionManager.estimatedCoveragePercent))",
                        unit: "%"
                    )
                    StatCard(
                        label: l10n("rescan.colors"),
                        value: vm.heatmapGenerated
                            ? l10n("rescan.colors.active")
                            : (vm.originalMesh != nil ? l10n("rescan.colors.ready") : l10n("rescan.colors.loading")),
                        tint: vm.heatmapGenerated
                            ? ScanArtTheme.statusGood
                            : (vm.originalMesh != nil ? ScanArtTheme.accent : ScanArtTheme.statusWarning)
                    )
                }

                // Page 2 — on-demand volume estimate
                HStack(spacing: ScanArtTheme.spacingS) {
                    if let vol = vm.estimatedVolumeLiters {
                        StatCard(
                            label: vm.projectType == .excavation ? l10n("rescan.volume.excavation") : l10n("rescan.volume.plaster"),
                            value: String(format: "%.1f", vol),
                            unit: "L",
                            tint: ScanArtTheme.accent
                        )
                        StatCard(
                            label: l10n("rescan.cubicMeters"),
                            value: String(format: "%.3f", vol / 1000),
                            unit: "m³"
                        )
                    } else {
                        volumePrompt(vm: vm)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 100)

            heatmapRow(vm: vm)

            PrimaryButton(
                l10n("rescan.finish"),
                systemImage: "checkmark.circle.fill",
                isEnabled: vm.canFinish
            ) {
                isShowingFinishSheet = true
            }
        }
    }

    @ViewBuilder
    private func heatmapRow(vm: RescanViewModel) -> some View {
        HStack(spacing: ScanArtTheme.spacingS) {
            Button {
                vm.resetScan()
            } label: {
                Label(l10n("action.reset"), systemImage: "arrow.counterclockwise")
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                            .fill(ScanArtTheme.surfaceElevated)
                    )
            }

            if vm.heatmapGenerated {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ScanArtTheme.statusGood)
                    Text(l10n("rescan.heatmapActive"))
                        .font(ScanArtTheme.body(14))
                        .foregroundStyle(ScanArtTheme.statusGood)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                        .fill(ScanArtTheme.surfaceElevated)
                )
            } else {
                Button {
                    vm.generateHeatmap()
                } label: {
                    Label(l10n("rescan.heatmap"), systemImage: "paintpalette.fill")
                        .font(ScanArtTheme.body(14))
                        .foregroundStyle(
                            vm.originalMesh != nil
                                ? ScanArtTheme.accent
                                : ScanArtTheme.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                                .fill(ScanArtTheme.surfaceElevated)
                        )
                }
                .disabled(vm.originalMesh == nil)
            }
        }
    }

    @ViewBuilder
    private func volumePrompt(vm: RescanViewModel) -> some View {
        HStack(spacing: ScanArtTheme.spacingS) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.projectType.volumeLabel.uppercased())
                    .font(ScanArtTheme.label())
                    .foregroundStyle(ScanArtTheme.textTertiary)
                if vm.isComputingVolume {
                    HStack(spacing: 8) {
                        ProgressView().tint(ScanArtTheme.accent).scaleEffect(0.8)
                        Text(l10n("rescan.calculating"))
                            .font(ScanArtTheme.body(13))
                            .foregroundStyle(ScanArtTheme.textSecondary)
                    }
                } else {
                    Button {
                        vm.computeVolumeOnce()
                    } label: {
                        Label(
                            vm.originalMesh != nil ? l10n("action.calculate") : l10n("rescan.loadingMesh"),
                            systemImage: "function"
                        )
                        .font(ScanArtTheme.body(13))
                        .foregroundStyle(
                            vm.originalMesh != nil
                                ? ScanArtTheme.accent
                                : ScanArtTheme.textTertiary
                        )
                    }
                    .disabled(vm.originalMesh == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ScanArtTheme.spacingM)
            .background(
                RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                    .fill(ScanArtTheme.surfaceElevated)
            )
        }
    }

    private struct ThicknessColorLegend: View {
        let targetMM: Double
        let toleranceMM: Double
        let unit: MeasurementUnit

        private var stops: [ColorStop] {
            ThicknessColorMapper.liveLegend(desiredThicknessMM: targetMM, toleranceMM: toleranceMM)
        }

        var body: some View {
            HStack(spacing: 10) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b))
                            .frame(width: 9, height: 9)
                        Text(rangeLabel(index: index))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        private func rangeLabel(index: Int) -> String {
            let lower = targetMM - toleranceMM
            let upper = targetMM + toleranceMM
            let thick = upper * 1.3
            switch index {
            case 0: return "< \(fmt(lower))"
            case 1: return "\(fmt(lower))–\(fmt(upper))"
            case 2: return "\(fmt(upper))–\(fmt(thick))"
            default: return "> \(fmt(thick))"
            }
        }

        private func fmt(_ mm: Double) -> String {
            switch unit {
            case .millimeters: return "\(Int(mm.rounded()))mm"
            case .centimeters: return String(format: "%.1fcm", mm / 10)
            case .inches:      return String(format: "%.2f\"", mm / 25.4)
            }
        }
    }

    private func errorToast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(ScanArtTheme.body(13))
                .foregroundStyle(.white)
                .padding(ScanArtTheme.spacingM)
                .background(ScanArtTheme.statusDanger, in: RoundedRectangle(cornerRadius: ScanArtTheme.radiusM))
                .padding(.bottom, 160)
        }
    }

    private var finishSheet: some View {
        NavigationStack {
            Form {
                Section(l10n("scan.label.optional")) {
                    TextField(l10n("rescan.label.placeholder"), text: $scanLabel)
                }
            }
            .navigationTitle(l10n("rescan.save"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n("action.cancel")) { isShowingFinishSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.vm?.isSaving == true ? l10n("action.saving") : l10n("action.save")) {
                        Task {
                            await viewModel.vm?.finishAndSave(label: scanLabel)
                            isShowingFinishSheet = false
                        }
                    }
                    .disabled(viewModel.vm?.isSaving == true)
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

/// See `ScanViewModelBox` in ScanView.swift for why this forwarding is
/// necessary (lazy construction + nested-ObservableObject propagation).
@MainActor
final class RescanViewModelBox: ObservableObject {
    @Published var vm: RescanViewModel? {
        didSet { resubscribe() }
    }
    private var cancellable: AnyCancellable?

    private func resubscribe() {
        cancellable = vm?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
