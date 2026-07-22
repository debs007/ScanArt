import SwiftUI
import ARKit
import Combine
import ScanArtAR
import ScanArtUI
import ScanArtCore

struct RescanView: View {
    let projectID: UUID
    @Binding var path: NavigationPath
    @Environment(\.diContainer) private var di

    @StateObject private var viewModel = RescanViewModelBox()
    @State private var isShowingFinishSheet = false
    @State private var scanLabel = ""

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
                    bottomBar(vm: vm)
                }
                .padding(ScanArtTheme.spacingM)

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
            CoverageRing(percent: vm.sessionManager.estimatedCoveragePercent)
        }
    }

    @ViewBuilder
    private func bottomBar(vm: RescanViewModel) -> some View {
        VStack(spacing: ScanArtTheme.spacingS) {
            // Color legend — only visible once the heatmap is actually applied.
            if vm.heatmapGenerated {
                ThicknessColorLegend(labels: vm.projectType.legendLabels)
            }

            // Swipeable stat pages — page dots stay within the fixed frame.
            TabView {
                // Page 1 — scan progress
                HStack(spacing: ScanArtTheme.spacingS) {
                    StatCard(
                        label: "Mesh",
                        value: "\(vm.sessionManager.meshAnchorCount)",
                        unit: "anchors"
                    )
                    StatCard(
                        label: "Coverage",
                        value: "\(Int(vm.sessionManager.estimatedCoveragePercent))",
                        unit: "%"
                    )
                    StatCard(
                        label: "Colors",
                        value: vm.heatmapGenerated ? "Active" : (vm.originalMesh != nil ? "Ready" : "Loading"),
                        tint: vm.heatmapGenerated
                            ? ScanArtTheme.statusGood
                            : (vm.originalMesh != nil ? ScanArtTheme.accent : ScanArtTheme.statusWarning)
                    )
                }

                // Page 2 — on-demand volume estimate
                HStack(spacing: ScanArtTheme.spacingS) {
                    if let vol = vm.estimatedVolumeLiters {
                        StatCard(
                            label: vm.projectType == .excavation ? "Excav. Vol." : "Plaster Vol.",
                            value: String(format: "%.1f", vol),
                            unit: "L",
                            tint: ScanArtTheme.accent
                        )
                        StatCard(
                            label: "Cubic Meters",
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

            // Heatmap + Reset row — sits above Finish Rescan, never scrolls.
            heatmapRow(vm: vm)

            // Static — never participates in the swipe gesture.
            PrimaryButton(
                "Finish Rescan",
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
            // Reset — always enabled; restarts the ARKit session and clears heatmap.
            Button {
                vm.resetScan()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
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
                // Heatmap active indicator replaces the button once applied.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ScanArtTheme.statusGood)
                    Text("Heatmap Active")
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
                // Generate Heatmap — enabled once the original mesh (and its hash) is ready.
                Button {
                    vm.generateHeatmap()
                } label: {
                    Label("Heatmap", systemImage: "paintpalette.fill")
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
                        Text("Calculating…")
                            .font(ScanArtTheme.body(13))
                            .foregroundStyle(ScanArtTheme.textSecondary)
                    }
                } else {
                    Button {
                        vm.computeVolumeOnce()
                    } label: {
                        Label(
                            vm.originalMesh != nil ? "Calculate" : "Loading mesh…",
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
        var labels: [String]

        private static let colors: [Color] = [
            Color(red: 0.14, green: 0.38, blue: 0.95),
            Color(red: 0.92, green: 0.88, blue: 0.12),
            Color(red: 0.14, green: 0.88, blue: 0.30),
            Color(red: 0.95, green: 0.52, blue: 0.10),
            Color(red: 0.95, green: 0.12, blue: 0.12),
        ]

        var body: some View {
            HStack(spacing: 10) {
                ForEach(Array(zip(Self.colors, labels).enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 4) {
                        Circle().fill(pair.0).frame(width: 9, height: 9)
                        Text(pair.1)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Section("Label (optional)") {
                    TextField("e.g. After Second Coat", text: $scanLabel)
                }
            }
            .navigationTitle("Save Rescan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingFinishSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.vm?.isSaving == true ? "Saving…" : "Save") {
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
