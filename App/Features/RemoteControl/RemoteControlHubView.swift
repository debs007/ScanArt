import SwiftUI
import ScanArtUI

/// Entry point: lets the user choose Broadcast or Join Room.
struct RemoteControlHubView: View {
    @State private var session = RemoteControlSession()
    @State private var mode: Mode?

    private enum Mode { case broadcasting, controlling }

    var body: some View {
        Group {
            switch mode {
            case .broadcasting:
                BroadcasterView(session: session) { mode = nil }
            case .controlling:
                ControllerView(session: session) { mode = nil }
            case .none:
                hubContent
            }
        }
        .scanArtScreenBackground()
        .navigationTitle("Remote Control")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hubContent: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                heroSection
                    .padding(.top, ScanArtTheme.spacingXL)

                Divider()
                    .background(ScanArtTheme.surfaceBorder)

                VStack(spacing: ScanArtTheme.spacingS) {
                    PrimaryButton("Broadcast Screen", systemImage: "dot.radiowaves.left.and.right") {
                        mode = .broadcasting
                    }
                    SecondaryButton("Join a Room", systemImage: "person.wave.2") {
                        mode = .controlling
                    }
                }

                infoCard
                    .padding(.top, ScanArtTheme.spacingXS)
            }
            .padding(.horizontal, ScanArtTheme.spacingL)
            .padding(.bottom, ScanArtTheme.spacingXL)
        }
    }

    private var heroSection: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            Image(systemName: "display.2")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundStyle(ScanArtTheme.accent)
            Text("Peer-to-Peer Screen Control")
                .font(ScanArtTheme.title())
                .foregroundStyle(ScanArtTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Share your screen and let another device control it — over WiFi or Bluetooth, no internet required.")
                .font(ScanArtTheme.body(14))
                .foregroundStyle(ScanArtTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var infoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingM) {
                infoRow(icon: "dot.radiowaves.left.and.right", color: ScanArtTheme.accent,
                        title: "Broadcast Screen",
                        body: "This device streams its screen and accepts remote taps from one controller at a time.")
                Divider().background(ScanArtTheme.surfaceBorder)
                infoRow(icon: "person.wave.2", color: ScanArtTheme.statusInfo,
                        title: "Join a Room",
                        body: "This device finds and connects to a broadcaster, shows its live screen, and sends your taps back.")
                Divider().background(ScanArtTheme.surfaceBorder)
                infoRow(icon: "wifi", color: ScanArtTheme.statusGood,
                        title: "WiFi or Bluetooth",
                        body: "Both devices must be nearby. Works on the same local network or direct Bluetooth — no cloud.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: ScanArtTheme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textPrimary)
                Text(body)
                    .font(ScanArtTheme.body(12))
                    .foregroundStyle(ScanArtTheme.textSecondary)
            }
        }
    }
}
