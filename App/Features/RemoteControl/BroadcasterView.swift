import SwiftUI
import UIKit
import ScanArtUI

/// Shown on the device that is broadcasting its screen.
/// Starts RPScreenRecorder + MCNearbyServiceAdvertiser on appear.
struct BroadcasterView: View {
    let session: RemoteControlSession
    let onStop: () -> Void

    @State private var cursorPosition: CGPoint = .zero
    @State private var showCursor = false

    var body: some View {
        ZStack {
            ScanArtTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: ScanArtTheme.spacingL) {
                statusCard
                    .padding(.horizontal, ScanArtTheme.spacingL)
                    .padding(.top, ScanArtTheme.spacingM)

                Spacer()

                if let error = session.captureError {
                    errorCard(error)
                        .padding(.horizontal, ScanArtTheme.spacingL)
                }

                PrimaryButton("Stop Broadcasting", systemImage: "stop.circle.fill", isDestructive: true) {
                    session.stopBroadcasting()
                    onStop()
                }
                .padding(.horizontal, ScanArtTheme.spacingL)
                .padding(.bottom, ScanArtTheme.spacingXL)
            }

            // Remote cursor indicator (shows where the controller is tapping)
            if showCursor {
                RemoteCursorView()
                    .position(cursorPosition)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.08), value: cursorPosition)
            }
        }
        .navigationTitle("Broadcasting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear { session.startBroadcasting() }
        .onDisappear {
            session.stopBroadcasting()
        }
        .onChange(of: session.touchEventID) { _, _ in
            guard let event = session.lastRemoteTouch else { return }
            handleRemoteTouch(event)
        }
    }

    // MARK: - Sub-views

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

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(spacing: ScanArtTheme.spacingM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ScanArtTheme.statusDanger)
                Text(message)
                    .font(ScanArtTheme.body(13))
                    .foregroundStyle(ScanArtTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Remote touch handling

    private func handleRemoteTouch(_ event: RemoteTouchEvent) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) else { return }

        let screenPoint = CGPoint(
            x: event.normalizedX * window.bounds.width,
            y: event.normalizedY * window.bounds.height
        )

        cursorPosition = screenPoint
        showCursor = true

        if event.kind == .tap {
            performTap(at: screenPoint, in: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showCursor = false }
        }
    }

    /// Hit-tests the view hierarchy and triggers the control at the given point.
    /// Tries UIControl first (covers UIKit), then accessibility activation (covers SwiftUI buttons).
    private func performTap(at point: CGPoint, in window: UIWindow) {
        guard let hitView = window.hitTest(point, with: nil) else { return }

        // Walk up the UIKit hierarchy for UIControl (buttons, sliders, etc.)
        var view: UIView? = hitView
        while let v = view {
            if let control = v as? UIControl {
                control.sendActions(for: .touchUpInside)
                return
            }
            view = v.superview
        }

        // SwiftUI Button activates via accessibility
        hitView.accessibilityActivate()
    }
}

// MARK: - Cursor indicator

private struct RemoteCursorView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(ScanArtTheme.accent.opacity(0.25))
                .frame(width: 48, height: 48)
            Circle()
                .stroke(ScanArtTheme.accent, lineWidth: 2)
                .frame(width: 48, height: 48)
            Circle()
                .fill(ScanArtTheme.accent)
                .frame(width: 8, height: 8)
        }
    }
}
