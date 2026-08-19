import SwiftUI
import Foundation
import UIKit
import ScanArtCore
import ScanArtUI

/// Type-safe navigation destinations for the app's single `NavigationStack`.
/// Kept as one enum (rather than per-feature stacks) since the spec's flows
/// cross features constantly (Project -> Scan -> Analysis -> Reports).
enum AppRoute: Hashable {
    case projectList
    case projectDetail(projectID: UUID)
    case scan(projectID: UUID)
    case rescan(projectID: UUID)
    case analysis(projectID: UUID, scanID: UUID)
    case reports(projectID: UUID)
    case settings
    case help
    case about
    case remoteControl
}

struct RootView: View {
    @State private var isShowingSplash = true
    @State private var path = NavigationPath()
    @State private var isCreatingProject = false

    // Root-level session: outlives any individual screen so broadcasting
    // continues while the user navigates the app freely.
    @State private var remoteSession = RemoteControlSession()

    @State private var remoteCursorPosition: CGPoint = .zero
    @State private var showRemoteCursor = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path, isCreatingProject: $isCreatingProject)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(remoteSession)
        .sheet(isPresented: $isCreatingProject) {
            CreateProjectView { newProjectID in
                isCreatingProject = false
                path.append(AppRoute.projectDetail(projectID: newProjectID))
            }
        }
        // Splash screen — on top of everything
        .overlay {
            if isShowingSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.3)) { isShowingSplash = false }
                }
                .transition(.opacity)
            }
        }
        // Floating broadcasting banner — visible on every screen while active
        .overlay(alignment: .bottom) {
            if remoteSession.role == .broadcaster {
                BroadcastingBanner(session: remoteSession)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: remoteSession.role == .broadcaster)
        // Remote cursor overlay — shows where the controller tapped
        .overlay {
            if showRemoteCursor {
                RemoteCursorOverlay(position: remoteCursorPosition)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.08), value: remoteCursorPosition)
            }
        }
        // Forward incoming touch events from the controller to the broadcaster's
        // current screen — works regardless of where the broadcaster has navigated.
        .onChange(of: remoteSession.touchEventID) { _, _ in
            guard remoteSession.role == .broadcaster,
                  let event = remoteSession.lastRemoteTouch else { return }
            handleRemoteTouch(event)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .projectList:
            ProjectListView(path: $path, isCreatingProject: $isCreatingProject)
        case .projectDetail(let projectID):
            ProjectDetailView(projectID: projectID, path: $path)
        case .scan(let projectID):
            ScanView(projectID: projectID, path: $path)
        case .rescan(let projectID):
            RescanView(projectID: projectID, path: $path)
        case .analysis(let projectID, let scanID):
            AnalysisView(projectID: projectID, scanID: scanID)
        case .reports(let projectID):
            ReportListView(projectID: projectID)
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        case .about:
            AboutView()
        case .remoteControl:
            RemoteControlHubView()
        }
    }

    // MARK: - Remote touch forwarding (cursor only — execution is in RemoteControlSession)

    private func handleRemoteTouch(_ event: RemoteTouchEvent) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) else { return }

        let screenPoint = CGPoint(
            x: event.normalizedX * window.bounds.width,
            y: event.normalizedY * window.bounds.height
        )

        remoteCursorPosition = screenPoint

        switch event.kind {
        case .touchBegan, .touchMoved:
            showRemoteCursor = true
        case .touchEnded:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showRemoteCursor = false }
        case .tap:
            showRemoteCursor = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showRemoteCursor = false }
        }
    }
}

// MARK: - Broadcasting banner

private struct BroadcastingBanner: View {
    let session: RemoteControlSession
    @State private var showingStopConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            PulsingDot()
            VStack(alignment: .leading, spacing: 2) {
                Text(session.isCaptureActive ? "Broadcasting" : "Starting…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Group {
                    if let peer = session.connectedPeers.first {
                        Text("Connected: \(peer.displayName)")
                    } else {
                        Text("Waiting for controller…")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Stop") {
                showingStopConfirm = true
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .confirmationDialog("Stop Broadcasting?", isPresented: $showingStopConfirm) {
                Button("Stop Broadcasting", role: .destructive) {
                    session.stopBroadcasting()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.6 : 1)
                .opacity(pulsing ? 0 : 0.8)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Remote cursor overlay

private struct RemoteCursorOverlay: View {
    let position: CGPoint

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
        .position(position)
    }
}
