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
    @Environment(LocalizationManager.self) private var l10n

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
        case .broadcaster: return l10n("remote.broadcasting")
        case .controller:  return l10n("remote.joinRoom")
        case .none:        return l10n("remote.title")
        }
    }

    // MARK: - Broadcasting active

    private var broadcastingActiveView: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                statusCard
                    .padding(.top, ScanArtTheme.spacingXL)

                instructionCard

                PrimaryButton(l10n("remote.stopBroadcasting"), systemImage: "stop.circle.fill", isDestructive: true) {
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
                        Text(session.isCaptureActive ? l10n("remote.broadcasting") : l10n("remote.starting"))
                            .font(ScanArtTheme.body(16))
                            .foregroundStyle(ScanArtTheme.textPrimary)
                        Text("\(l10n("remote.from")) \(UIDevice.current.name)")
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
                    Text(l10n("remote.connectedControllers"))
                        .font(ScanArtTheme.label())
                        .foregroundStyle(ScanArtTheme.textTertiary)
                    if session.connectedPeers.isEmpty {
                        Text(l10n("remote.waitingForDevice"))
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
                    Text(l10n("remote.useAppFreely"))
                        .font(ScanArtTheme.body(15))
                        .foregroundStyle(ScanArtTheme.textPrimary)
                    Text(l10n("remote.useAppFreelySubtitle"))
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
                    PrimaryButton(l10n("remote.broadcastScreen"), systemImage: "dot.radiowaves.left.and.right") {
                        session.startBroadcasting()
                    }
                    SecondaryButton(l10n("remote.joinARoom"), systemImage: "person.wave.2") {
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
            Text(l10n("remote.peerToPeerTitle"))
                .font(ScanArtTheme.title())
                .foregroundStyle(ScanArtTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(l10n("remote.peerToPeerSubtitle"))
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
                        title: l10n("remote.info.broadcastScreen.title"),
                        body: l10n("remote.info.broadcastScreen.body"))
                Divider().background(ScanArtTheme.surfaceBorder)
                infoRow(icon: "person.wave.2", color: ScanArtTheme.statusInfo,
                        title: l10n("remote.info.joinRoom.title"),
                        body: l10n("remote.info.joinRoom.body"))
                Divider().background(ScanArtTheme.surfaceBorder)
                infoRow(icon: "wifi", color: ScanArtTheme.statusGood,
                        title: l10n("remote.info.wifi.title"),
                        body: l10n("remote.info.wifi.body"))
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
