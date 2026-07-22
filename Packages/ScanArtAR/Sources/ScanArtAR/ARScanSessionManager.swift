import ARKit
import Combine
import ScanArtAlgorithms

public enum RelocalizationState: Sendable, Equatable {
    /// Not applicable — this is an original (first) scan, no relocalization needed.
    case notApplicable
    case relocalizing
    case relocalized
    case failed
}

/// Owns the live `ARSession` for both the original scan and rescans.
///
/// Alignment strategy (see ICPAligner.swift for the full rationale): a rescan
/// is started by loading the ORIGINAL scan's saved `ARWorldMap` as
/// `initialWorldMap`. ARKit's own visual-inertial relocalization then places
/// the new session in the exact same real-world coordinate frame as the
/// original — no post-hoc geometric alignment required for the common case.
/// `ICPAligner` (in ScanArtAlgorithms) is only invoked afterward, as an
/// optional refinement restricted to stable-reference faces.
@MainActor
public final class ARScanSessionManager: NSObject, ObservableObject {
    @Published public private(set) var trackingState: ARCamera.TrackingState = .notAvailable
    @Published public private(set) var relocalizationState: RelocalizationState = .notApplicable
    @Published public private(set) var meshAnchorCount: Int = 0
    @Published public private(set) var estimatedCoveragePercent: Double = 0
    @Published public private(set) var lastError: ScanArtSessionError?

    public let session = ARSession()

    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var trackingSamples: [Bool] = [] // true = .normal, for ScanQuality's stability ratio
    private var lastCoverageTime: Date = .distantPast
    private var coverageTask: Task<Void, Never>?

    override public init() {
        super.init()
        // Pin the delegate queue to the main queue so ARKit always calls our
        // @MainActor-isolated delegate methods on the right thread — no Task
        // dispatch overhead on every 60 Hz anchor-update callback.
        session.delegateQueue = DispatchQueue.main
        session.delegate = self
    }

    // MARK: - Session lifecycle

    public func startOriginalScan() {
        guard LiDARCapability.isSupported else {
            lastError = .lidarUnavailable
            return
        }
        let config = makeConfiguration()
        relocalizationState = .notApplicable
        resetTrackingBuffers()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    /// Reconfigures the already-running session with a previously saved world
    /// map to enable relocalization. The world map must be loaded off the main
    /// thread by the caller BEFORE this is invoked.
    ///
    /// Callers should start `startOriginalScan()` first so that ARSCNView
    /// always receives a live camera feed, then call this once the world map
    /// has been deserialized in the background.
    public func startRescanWithMap(_ worldMap: ARWorldMap) {
        guard LiDARCapability.isSupported else {
            lastError = .lidarUnavailable
            return
        }
        let config = makeConfiguration()
        config.initialWorldMap = worldMap
        relocalizationState = .relocalizing
        resetTrackingBuffers()
        // Do NOT pass .removeExistingAnchors — keeping the anchors already captured
        // during the initial startOriginalScan() phase means the live mesh stays
        // visible even if ARKit's relocalization is slow or never fully succeeds
        // (which happens when the original scan was small and had few visual features).
        // ARKit fires session(_:didUpdate:for:) for every kept anchor once tracking
        // is re-established, so the bookkeeping rebuilt by resetTrackingBuffers() is
        // quickly repopulated without the coverage flickering to zero.
        session.run(config, options: [.resetTracking])
    }

    public func pause() {
        session.pause()
    }

    public func stop() {
        session.pause()
        coverageTask?.cancel()
        coverageTask = nil
        meshAnchors.removeAll()
        meshAnchorCount = 0
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = LiDARCapability.supportsClassification ? .meshWithClassification : .mesh
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        return config
    }

    private func resetTrackingBuffers() {
        meshAnchors.removeAll()
        trackingSamples.removeAll()
        meshAnchorCount = 0
        estimatedCoveragePercent = 0
    }

    // MARK: - Output

    /// Converts every currently-tracked mesh anchor into a single world-space
    /// mesh. Safe to call repeatedly during a live scan for real-time preview.
    public func currentMeshBuffer() -> MeshBuffer {
        MeshAnchorConverter.convert(Array(meshAnchors.values))
    }

    public func captureWorldMap() async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map {
                    continuation.resume(returning: map)
                } else {
                    continuation.resume(throwing: error ?? ScanArtSessionError.worldMapCaptureFailed)
                }
            }
        }
    }

    public var trackingStabilityRatio: Double {
        guard !trackingSamples.isEmpty else { return 0 }
        return Double(trackingSamples.filter { $0 }.count) / Double(trackingSamples.count)
    }

    // MARK: - Anchor bookkeeping

    private func handle(updated anchors: [ARAnchor]) {
        var changed = false
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors[meshAnchor.identifier] = meshAnchor
                changed = true
            }
        }
        guard changed else { return }
        meshAnchorCount = meshAnchors.count
        scheduleCoverageUpdate()
    }

    /// Rate-limited to 2 Hz. Converts anchors → MeshBuffer on the main thread
    /// (cheap at this rate), then estimates coverage on a background thread so
    /// the main thread is never blocked by the O(vertex-count) computation.
    private func scheduleCoverageUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastCoverageTime) >= 0.5 else { return }
        lastCoverageTime = now

        // Snapshot the mesh on the main thread — MeshAnchorConverter reads Metal
        // buffers which are immutable after ARKit delivers the anchor callback.
        let mesh = MeshAnchorConverter.convert(Array(meshAnchors.values))

        coverageTask?.cancel()
        coverageTask = Task.detached(priority: .utility) { [weak self] in
            let coverage = ScanQualityAnalyzer().estimateCoverage(mesh: mesh)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.estimatedCoveragePercent = coverage }
        }
    }

    private func handle(removed anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors.removeValue(forKey: meshAnchor.identifier)
            }
        }
        meshAnchorCount = meshAnchors.count
    }
}

// MARK: - ARSessionDelegate

// session.delegateQueue is pinned to DispatchQueue.main in init, so every
// method below is guaranteed to run on the main thread — matching the
// @MainActor isolation of the class with zero Task-dispatch overhead.
extension ARScanSessionManager: ARSessionDelegate {
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        handle(updated: anchors)
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        handle(updated: anchors)
    }

    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        handle(removed: anchors)
    }

    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        trackingState = camera.trackingState
        trackingSamples.append(camera.trackingState == .normal)
        if trackingSamples.count > 600 { trackingSamples.removeFirst(trackingSamples.count - 600) }

        switch camera.trackingState {
        case .normal:
            if relocalizationState == .relocalizing { relocalizationState = .relocalized }
        case .limited(.relocalizing):
            relocalizationState = .relocalizing
        default:
            break
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        lastError = .sessionFailed(error.localizedDescription)
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        // Handled via trackingState changes.
    }
}

public enum ScanArtSessionError: Error, Sendable, Equatable {
    case lidarUnavailable
    case worldMapCaptureFailed
    case worldMapLoadFailed
    case sessionFailed(String)
}

/// Archives / restores `ARWorldMap` to disk. `ARWorldMap` conforms to
/// `NSSecureCoding`, so this uses `NSKeyedArchiver`/`NSKeyedUnarchiver` with
/// `requiringSecureCoding: true` — the pattern ARKit's own documentation and
/// sample code use for persisting world maps between sessions.
public enum WorldMapArchiver {
    public static func save(_ worldMap: ARWorldMap, to url: URL) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> ARWorldMap {
        let data = try Data(contentsOf: url)
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw ScanArtSessionError.worldMapLoadFailed
        }
        return map
    }
}
