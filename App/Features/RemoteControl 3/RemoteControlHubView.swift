import SwiftUI
import UIKit
import ScanArtUI

/// Entry point for remote control. Switches between three states driven by the
/// shared RemoteControlSession from the environment:
///   • no role   → show Broadcast / Join buttons
///   • broadcaster → show status card + "use app freely" instructions
///   • controller  → show ControllerView (peer browser + live stream)
struct RemoteControlHubView: View {
    @Environment(RemoteControlSession.self) private var session

    var body: some View {
        Group {
            switch session.role {
            case .broadcaster:
                broadcastingActiveView
            case .controller:
                ControllerView(session: session)
            case .none:
                hubContent
            }
        }
        .scanArtScreenBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        switch session.role {
        case .broadcaster: return "Broadcasting"
        case .controller: return "Join Room"
        case .none: return "Remote Control"
        }
    }

    // MARK: - Broadcasting active

    private var broadcastingActiveView: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                statusCard
                    .padding(.top, ScanArtTheme.spacingXL)

                instructionCard

                PrimaryButton("Stop Broadcasting", systemImage: "stop.circle.fill", isDestructive: true) {
                    session.stopBroadcasting()
                }
            }
            .padding(.horizontal, ScanArtTheme.spacingL)
            .padding(.bottom, ScanArtTheme.spacingXL + 60) // extra room above the banner
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(spacing: ScanArtTheme.spacingM) {
                HStack(spacing: ScanArtTheme.spacingM) {
                    captureStatusIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.isCaptureActive ? "Broadcasting" : "Starting…")
                            .font(ScanArtTheme.body(16))
                            .foregroundStyle(ScanArtTheme.textPrimary)
                        Text("From: \(UIDevice.current.name)")
                            .font(ScanArtTheme.body(12))
                            .foregroundStyle(ScanArtTheme.textSecondary)
                    }
                    Spacer()
                    Text("\(session.connectedPeers.count)")
                        .font(ScanArtTheme.numericDisplay(28))
                        .foregroundStyle(ScanArtTheme.accent)
                }

                Divider().background(ScanArtTheme.surfaceBorder)

                VStack(alignment: .leading, spacing: ScanArtTheme.spacingXS) {
                    Text("CONNECTED CONTROLLERS")
                        .font(ScanArtTheme.label())
                        .foregroundStyle(ScanArtTheme.textTertiary)
                    if session.connectedPeers.isEmpty {
                        Text("Waiting for a device to join…")
                            .font(ScanArtTheme.body(14))
                            .foregroundStyle(ScanArtTheme.textTertiary)
                    } else {
                        ForEach(session.connectedPeers, id: \.displayName) { peer in
                            HStack(spacing: ScanArtTheme.spacingS) {
                                Circle()
                                    .fill(ScanArtTheme.statusGood)
                                    .frame(width: 7, height: 7)
                                Text(peer.displayName)
                                    .font(ScanArtTheme.body(14))
                                    .foregroundStyle(ScanArtTheme.statusGood)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var captureStatusIcon: some View {
        ZStack {
            Circle()
                .fill(session.isCaptureActive
                      ? ScanArtTheme.statusGood.opacity(0.18)
                      : ScanArtTheme.statusWarning.opacity(0.18))
                .frame(width: 44, height: 44)
            Image(systemName: session.isCaptureActive ? "dot.radiowaves.left.and.right" : "ellipsis")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(session.isCaptureActive ? ScanArtTheme.statusGood : ScanArtTheme.statusWarning)
        }
    }

    private var instructionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: ScanArtTheme.spacingM) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use the app freely")
                        .font(ScanArtTheme.body(15))
                        .foregroundStyle(ScanArtTheme.textPrimary)
                    Text("Navigate anywhere — the controller sees whatever screen you're on and can tap to control it. A broadcasting indicator stays visible at the bottom of every screen.")
                        .font(ScanArtTheme.body(13))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Main hub

    private var hubContent: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                heroSection
                    .padding(.top, ScanArtTheme.spacingXL)

                Divider()
                    .background(ScanArtTheme.surfaceBorder)

                VStack(spacing: ScanArtTheme.spacingS) {
                    PrimaryButton("Broadcast Screen", systemImage: "dot.radiowaves.left.and.right") {
                        session.startBroadcasting()
                    }
                    SecondaryButton("Join a Room", systemImage: "person.wave.2") {
                        session.startBrowsing()
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
                        body: "Streams your screen to a controller. Navigate the app normally — the controller sees everything you do.")
                Divider().background(ScanArtTheme.surfaceBorder)
                infoRow(icon: "person.wave.2", color: ScanArtTheme.statusInfo,
                        title: "Join a Room",
                        body: "Connects to a broadcaster, shows their live screen, and sends your taps back to control it.")
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
