import SwiftUI
import ARKit
import Combine
import ScanArtAR
import ScanArtUI
import ScanArtCore

struct ScanView: View {
    let projectID: UUID
    @Binding var path: NavigationPath
    @Environment(\.diContainer) private var di

    @StateObject private var viewModel = ScanViewModelBox()
    @State private var isShowingFinishSheet = false
    @State private var scanLabel = ""

    var body: some View {
        ZStack {
            if let vm = viewModel.vm {
                ARCameraView(sessionManager: vm.sessionManager, mode: .original)
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
                viewModel.vm = ScanViewModel(projectID: projectID, di: di)
                viewModel.vm?.start()
            }
        }
        .onDisappear { viewModel.vm?.stop() }
        .sheet(isPresented: $isShowingFinishSheet) {
            finishSheet
        }
        .onChange(of: viewModel.vm?.didSave) { _, didSave in
            if didSave == true { path.removeLast() }
        }
    }

    @ViewBuilder
    private func topBar(vm: ScanViewModel) -> some View {
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
    private func bottomBar(vm: ScanViewModel) -> some View {
        VStack(spacing: ScanArtTheme.spacingS) {
            trackingBanner(vm: vm)
            HStack(spacing: ScanArtTheme.spacingS) {
                StatCard(label: "Mesh", value: "\(vm.sessionManager.meshAnchorCount)", unit: "anchors")
                StatCard(label: "Coverage", value: "\(Int(vm.sessionManager.estimatedCoveragePercent))", unit: "%")
            }
            PrimaryButton("Finish Scan", systemImage: "checkmark.circle.fill", isEnabled: vm.canFinish) {
                isShowingFinishSheet = true
            }
        }
    }

    @ViewBuilder
    private func trackingBanner(vm: ScanViewModel) -> some View {
        if case .limited(let reason) = vm.sessionManager.trackingState {
            Text(trackingMessage(for: reason))
                .font(ScanArtTheme.body(13))
                .foregroundStyle(ScanArtTheme.textPrimary)
                .padding(ScanArtTheme.spacingS)
                .frame(maxWidth: .infinity)
                .glassPanel(cornerRadius: ScanArtTheme.radiusS)
        }
    }

    private func trackingMessage(for reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: return "Move the device slowly to begin tracking…"
        case .excessiveMotion: return "Moving too fast — slow down."
        case .insufficientFeatures: return "Point at a more textured surface."
        case .relocalizing: return "Finding your position…"
        @unknown default: return "Tracking is limited."
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
                .padding(.bottom, 140)
        }
    }

    private var finishSheet: some View {
        NavigationStack {
            Form {
                Section("Label (optional)") {
                    TextField("e.g. Original Scan", text: $scanLabel)
                }
            }
            .navigationTitle("Save Scan")
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
        .presentationDetents([.height(220)])
    }
}

/// `ScanView` needs to construct its `ScanViewModel` lazily once the DI
/// container is available from the environment (not yet available at
/// `init`), so this small box lets `@StateObject` hold a settable slot rather
/// than requiring the view model to exist before the view does.
///
/// Just wrapping `vm` in `@Published` is NOT enough on its own: `@Published`
/// only fires when the `vm` slot itself is reassigned, not when a property
/// *inside* the referenced `ScanViewModel` changes — so without the explicit
/// forwarding below, coverage %, tracking state, and save progress would
/// never trigger a re-render after the initial assignment.
@MainActor
final class ScanViewModelBox: ObservableObject {
    @Published var vm: ScanViewModel? {
        didSet { resubscribe() }
    }
    private var cancellable: AnyCancellable?

    private func resubscribe() {
        cancellable = vm?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
