import SwiftUI
import UIKit
import ScanArtUI

/// Shown on the device that is controlling a broadcaster.
/// Displays the live screen stream and forwards taps back as RemoteTouchEvents.
struct ControllerView: View {
    let session: RemoteControlSession
    let onDisconnect: () -> Void

    var body: some View {
        Group {
            if session.connectedPeers.isEmpty {
                peerBrowserView
            } else {
                activeControlView
            }
        }
        .scanArtScreenBackground()
        .navigationTitle("Join Room")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear { session.startBrowsing() }
        .onDisappear { session.disconnect() }
    }

    // MARK: - Peer browser (pre-connect)

    private var peerBrowserView: some View {
        VStack(spacing: ScanArtTheme.spacingL) {
            searchingHeader
                .padding(.top, ScanArtTheme.spacingXL)

            if session.availablePeers.isEmpty {
                emptyPeersCard
                    .padding(.horizontal, ScanArtTheme.spacingL)
            } else {
                peersSection
            }

            Spacer()

            SecondaryButton("Cancel", systemImage: "xmark.circle") {
                session.disconnect()
                onDisconnect()
            }
            .padding(.horizontal, ScanArtTheme.spacingL)
            .padding(.bottom, ScanArtTheme.spacingXL)
        }
    }

    private var searchingHeader: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(ScanArtTheme.accent)
            Text("Searching for broadcasters…")
                .font(ScanArtTheme.body())
                .foregroundStyle(ScanArtTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPeersCard: some View {
        GlassCard {
            VStack(spacing: ScanArtTheme.spacingM) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(ScanArtTheme.textTertiary)
                Text("No broadcasters found")
                    .font(ScanArtTheme.body(15))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                Text("Open Scan Art on the other device, tap Remote Control → Broadcast Screen, then return here.")
                    .font(ScanArtTheme.body(13))
                    .foregroundStyle(ScanArtTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
            Text("AVAILABLE ROOMS")
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.textTertiary)
                .padding(.horizontal, ScanArtTheme.spacingL)

            ForEach(session.availablePeers, id: \.displayName) { peer in
                Button {
                    session.connect(to: peer)
                } label: {
                    HStack(spacing: ScanArtTheme.spacingM) {
                        ZStack {
                            Circle().fill(ScanArtTheme.accentMuted).frame(width: 44, height: 44)
                            Image(systemName: "ipad.and.iphone")
                                .foregroundStyle(ScanArtTheme.accent)
                                .font(.system(size: 17, weight: .light))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.displayName)
                                .font(ScanArtTheme.body(16))
                                .foregroundStyle(ScanArtTheme.textPrimary)
                            Text("Broadcasting · tap to connect")
                                .font(ScanArtTheme.body(12))
                                .foregroundStyle(ScanArtTheme.statusGood)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(ScanArtTheme.accent)
                            .font(.system(size: 22, weight: .light))
                    }
                    .padding(ScanArtTheme.spacingM)
                    .background(
                        RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                            .fill(ScanArtTheme.surfaceElevated)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ScanArtTheme.spacingL)
            }
        }
    }

    // MARK: - Active control (post-connect)

    private var activeControlView: some View {
        VStack(spacing: 0) {
            connectionBar

            GeometryReader { geo in
                if let image = session.latestFrame {
                    screenView(image: image, containerSize: geo.size)
                } else {
                    waitingView
                }
            }
        }
    }

    private var connectionBar: some View {
        HStack {
            Label("Connected", systemImage: "circle.fill")
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.statusGood)
                .labelStyle(.titleAndIcon)

            if let peer = session.connectedPeers.first {
                Text("· \(peer.displayName)")
                    .font(ScanArtTheme.body(13))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Disconnect") {
                session.disconnect()
                onDisconnect()
            }
            .font(ScanArtTheme.body(14))
            .foregroundStyle(ScanArtTheme.statusDanger)
        }
        .padding(.horizontal, ScanArtTheme.spacingL)
        .padding(.vertical, ScanArtTheme.spacingM)
        .background(ScanArtTheme.backgroundSecondary)
    }

    private func screenView(image: UIImage, containerSize: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: containerSize.width, height: containerSize.height)
            .background(Color.black)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let frame = imageDisplayFrame(imageSize: image.size, in: containerSize)
                        guard frame.width > 0, frame.height > 0 else { return }
                        let nx = (value.location.x - frame.minX) / frame.width
                        let ny = (value.location.y - frame.minY) / frame.height
                        guard (0...1).contains(nx), (0...1).contains(ny) else { return }
                        session.sendTouch(RemoteTouchEvent(kind: .tap, normalizedX: nx, normalizedY: ny))
                    }
            )
    }

    private var waitingView: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(ScanArtTheme.accent)
            Text("Waiting for screen stream…")
                .font(ScanArtTheme.body())
                .foregroundStyle(ScanArtTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Coordinate mapping

    /// Returns the CGRect that the image actually occupies inside the container
    /// when displayed with `.aspectRatio(contentMode: .fit)`.
    private func imageDisplayFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let cAspect = container.width / container.height
        let iAspect = imageSize.width / imageSize.height
        if iAspect > cAspect {
            let w = container.width
            let h = w / iAspect
            return CGRect(x: 0, y: (container.height - h) / 2, width: w, height: h)
        } else {
            let h = container.height
            let w = h * iAspect
            return CGRect(x: (container.width - w) / 2, y: 0, width: w, height: h)
        }
    }
}
