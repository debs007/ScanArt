import SwiftUI
import ScanArtAR
import ScanArtUI

/// The spec's device gate happens here, before any project/scan flow is
/// reachable: "detect LiDAR availability before starting... show 'This device
/// is not supported.'"
struct SplashView: View {
    let onFinished: () -> Void
    @State private var isCapable: Bool? = nil

    var body: some View {
        ZStack {
            ScanArtTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: ScanArtTheme.spacingL) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                Text("Scan Art")
                    .font(ScanArtTheme.numericDisplay(30))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                Text("LiDAR Plaster Thickness Measurement")
                    .font(ScanArtTheme.body())
                    .foregroundStyle(ScanArtTheme.textSecondary)

                if isCapable == false {
                    unsupportedDeviceNotice
                } else {
                    ProgressView()
                        .tint(ScanArtTheme.accent)
                        .padding(.top, ScanArtTheme.spacingM)
                }
            }
            .padding(ScanArtTheme.spacingXL)
        }
        .task {
            // Deliberately checked once, on-device, rather than trusting a
            // hardcoded model list — see LiDARCapability's doc comment.
            let capable = LiDARCapability.isSupported
            isCapable = capable
            if capable {
                try? await Task.sleep(for: .milliseconds(500)) // brief, intentional brand moment
                onFinished()
            }
        }
    }

    private var unsupportedDeviceNotice: some View {
        VStack(spacing: ScanArtTheme.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(ScanArtTheme.statusDanger)
            Text("This device is not supported.")
                .font(ScanArtTheme.title(18))
                .foregroundStyle(ScanArtTheme.textPrimary)
            Text("Scan Art requires a LiDAR Scanner, available on iPhone Pro and iPad Pro models.")
                .font(ScanArtTheme.body(13))
                .foregroundStyle(ScanArtTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(ScanArtTheme.spacingM)
        .glassPanel()
        .padding(.top, ScanArtTheme.spacingM)
    }
}
