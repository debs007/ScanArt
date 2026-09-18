import SwiftUI
import ScanArtAR
import ScanArtUI

/// The spec's device gate happens here, before any project/scan flow is
/// reachable: "detect LiDAR availability before starting... show 'This device
/// is not supported.'"
struct SplashView: View {
    let onFinished: () -> Void
    @State private var isCapable: Bool? = nil
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        ZStack {
            ScanArtTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: ScanArtTheme.spacingL) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                Text(l10n("app.name"))
                    .font(ScanArtTheme.numericDisplay(30))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                Text(l10n("splash.tagline"))
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
            Text(l10n("splash.unsupported"))
                .font(ScanArtTheme.title(18))
                .foregroundStyle(ScanArtTheme.textPrimary)
            Text(l10n("splash.unsupportedNote"))
                .font(ScanArtTheme.body(13))
                .foregroundStyle(ScanArtTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(ScanArtTheme.spacingM)
        .glassPanel()
        .padding(.top, ScanArtTheme.spacingM)
    }
}
