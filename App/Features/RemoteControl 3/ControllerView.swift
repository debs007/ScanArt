import SwiftUI
import UIKit
import ScanArtUI

/// Shown on the device that is controlling a broadcaster.
/// Displays the live screen stream and forwards taps back as RemoteTouchEvents.
struct ControllerView: View {
    let session: RemoteControlSession
    @Environment(LocalizationManager.self) private var l10n

    @State private var isDragging = false
    @State private var tapIndicatorPoint: CGPoint?
    @State private var showingKeyboardInput = false
    @State private var keyboardInputText = ""

    var body: some View {
        Group {
            if session.connectedPeers.isEmpty {
                peerBrowserView
            } else {
                activeControlView
            }
        }
        .scanArtScreenBackground()
        .navigationTitle(l10n("remote.joinRoom"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear { session.startBrowsing() }
        .onDisappear { session.disconnect() }
        .sheet(isPresented: $showingKeyboardInput) {
            keyboardInputSheet
        }
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

            SecondaryButton(l10n("action.cancel"), systemImage: "xmark.circle") {
                session.disconnect()
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
            Text(l10n("remote.searchingBroadcasters"))
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
                Text(l10n("remote.noBroadcastersFound"))
                    .font(ScanArtTheme.body(15))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                Text(l10n("remote.noBroadcastersNote"))
                    .font(ScanArtTheme.body(13))
                    .foregroundStyle(ScanArtTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
            Text(l10n("remote.availableRooms"))
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
                            Text(l10n("remote.broadcasting.tapToConnect"))
                                .font(ScanArtTheme.body(12))
                                .foregroundStyle(ScanArtTheme.statusGood)
                        }
                        Spacer()
                        if session.isConnecting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(ScanArtTheme.accent)
                                .font(.system(size: 22, weight: .light))
                        }
                    }
                    .padding(ScanArtTheme.spacingM)
                    .background(
                        RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                            .fill(ScanArtTheme.surfaceElevated)
                    )
                }
                .buttonStyle(.plain)
                .disabled(session.isConnecting)
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
            Label(l10n("remote.connectedTo"), systemImage: "circle.fill")
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

            // Keyboard button — lets the controller type text into a remote text field.
            Button {
                showingKeyboardInput = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                    .padding(.trailing, ScanArtTheme.spacingS)
            }

            Button(l10n("action.disconnect")) {
                session.disconnect()
            }
            .font(ScanArtTheme.body(14))
            .foregroundStyle(ScanArtTheme.statusDanger)
        }
        .padding(.horizontal, ScanArtTheme.spacingL)
        .padding(.vertical, ScanArtTheme.spacingM)
        .background(ScanArtTheme.backgroundSecondary)
    }

    // MARK: - Keyboard input sheet

    private var keyboardInputSheet: some View {
        NavigationStack {
            VStack(spacing: ScanArtTheme.spacingL) {
                Text(l10n("remote.keyboard.prompt"))
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField(l10n("remote.keyboard.placeholder"), text: $keyboardInputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, ScanArtTheme.spacingL)
            .navigationTitle(l10n("remote.keyboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n("action.cancel")) {
                        keyboardInputText = ""
                        showingKeyboardInput = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n("action.send")) {
                        let text = keyboardInputText
                        if !text.isEmpty {
                            session.sendTextInput(text)
                            keyboardInputText = ""
                        }
                        showingKeyboardInput = false
                    }
                    .fontWeight(.semibold)
                    .disabled(keyboardInputText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Screen view with gesture forwarding

    private func screenView(image: UIImage, containerSize: CGSize) -> some View {
        let frame = imageDisplayFrame(imageSize: image.size, in: containerSize)

        func normalized(_ location: CGPoint) -> (nx: Double, ny: Double)? {
            guard frame.width > 0, frame.height > 0 else { return nil }
            let nx = (location.x - frame.minX) / frame.width
            let ny = (location.y - frame.minY) / frame.height
            guard (0...1).contains(nx), (0...1).contains(ny) else { return nil }
            return (Double(nx), Double(ny))
        }

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: containerSize.width, height: containerSize.height)

            if let pt = tapIndicatorPoint {
                Circle()
                    .stroke(Color.white.opacity(0.75), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .position(x: pt.x, y: pt.y)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            }
        }
        .background(Color.black)
        .animation(.easeOut(duration: 0.2), value: tapIndicatorPoint == nil)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let (nx, ny) = normalized(value.location) else { return }
                    if !isDragging {
                        isDragging = true
                        session.sendTouch(RemoteTouchEvent(kind: .touchBegan, normalizedX: nx, normalizedY: ny))
                    } else {
                        session.sendTouch(RemoteTouchEvent(kind: .touchMoved, normalizedX: nx, normalizedY: ny))
                    }
                }
                .onEnded { value in
                    isDragging = false
                    guard let (nx, ny) = normalized(value.location) else { return }
                    session.sendTouch(RemoteTouchEvent(kind: .touchEnded, normalizedX: nx, normalizedY: ny))
                    session.sendTouch(RemoteTouchEvent(kind: .tap, normalizedX: nx, normalizedY: ny))
                    withAnimation(.easeOut(duration: 0.15)) { tapIndicatorPoint = value.location }
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        withAnimation(.easeIn(duration: 0.15)) { tapIndicatorPoint = nil }
                    }
                }
        )
    }

    private var waitingView: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(ScanArtTheme.accent)
            Text(l10n("remote.waitingForStream"))
                .font(ScanArtTheme.body())
                .foregroundStyle(ScanArtTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Coordinate mapping

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
