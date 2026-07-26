import SwiftUI
import ARKit
import SceneKit
import ScanArtAlgorithms
import ScanArtCore

// MARK: - Visualization mode

/// Describes how the live AR mesh overlay is rendered.
public enum ScanVisualizationMode {
    /// Original scan: white semi-transparent solid mesh so coverage is visible
    /// while the wall remains visible through the 40% alpha fill.
    case original
    /// Rescan: mesh rendered white during active scanning. Call
    /// `ARCameraView.heatmapRequested = true` to trigger a one-shot pass that
    /// colors each vertex by its estimated distance to the original surface.
    ///
    /// `alignmentTransform` maps current-session world-space coordinates into the
    /// original-session coordinate frame so the hash query is always done in the
    /// same frame as the stored original mesh. Starts as `.identity`; updated
    /// once background ICP on stable reference faces converges.
    case rescan(originalMesh: MeshBuffer, alignmentTransform: simd_float4x4, targetThicknessMM: Float, toleranceMM: Float)
}

// MARK: - ARCameraView

/// Live camera view used during scanning and rescanning.
///
/// In rescan mode the mesh is rendered white (zero per-vertex color work) until
/// the user explicitly requests the heatmap via `heatmapRequested = true`. After
/// the heatmap is applied each mesh anchor also gets a floating AR text label
/// showing the average measured distance for that region.
public struct ARCameraView: UIViewRepresentable {
    @ObservedObject public var sessionManager: ARScanSessionManager
    public var mode: ScanVisualizationMode
    /// When true the coordinator arms a one-shot heatmap pass on the next render frame.
    public var heatmapRequested: Bool = false
    /// Increment to clear heatmap state and AR labels so the user can rescan fresh.
    public var resetTrigger: Int = 0
    /// Unit used to format the AR text labels.
    public var measurementUnit: MeasurementUnit = .centimeters
    /// Whether the project measures added material (plaster) or removed material
    /// (excavation) — used only for label formatting context.
    public var projectType: ProjectType = .plaster

    public init(
        sessionManager: ARScanSessionManager,
        mode: ScanVisualizationMode = .original,
        heatmapRequested: Bool = false,
        resetTrigger: Int = 0,
        measurementUnit: MeasurementUnit = .centimeters,
        projectType: ProjectType = .plaster
    ) {
        self.sessionManager = sessionManager
        self.mode = mode
        self.heatmapRequested = heatmapRequested
        self.resetTrigger = resetTrigger
        self.measurementUnit = measurementUnit
        self.projectType = projectType
    }

    public func makeCoordinator() -> ARMeshCoordinator {
        ARMeshCoordinator(mode: mode)
    }

    public func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.autoenablesDefaultLighting = false
        view.automaticallyUpdatesLighting = false
        view.delegate = context.coordinator
        view.session = sessionManager.session
        sessionManager.session.delegate = sessionManager
        return view
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.setMode(mode)
        context.coordinator.handleHeatmap(requested: heatmapRequested, resetTrigger: resetTrigger)
        context.coordinator.setDisplayConfig(unit: measurementUnit, projectType: projectType)
        if uiView.session.delegate !== sessionManager {
            uiView.session.delegate = sessionManager
        }
    }
}

// MARK: - Coordinator

/// Owns the SceneKit side of the AR mesh overlay.
///
/// Thread model: `setMode`, `handleHeatmap`, and `setDisplayConfig` are always
/// called on the main thread. The `ARSCNViewDelegate` callbacks are called on
/// the render thread. All shared mutable state is protected by `lock`.
///
/// Heatmap lifecycle:
///   1. Active rescan: mesh nodes rendered white — zero color work per frame.
///   2. User taps "Generate Heatmap" → `heatmapRequested = true`.
///   3. `handleHeatmap` arms `_heatmapRequested` (only if hash is ready).
///   4. `renderer(_:updateAtTime:)` Phase 1: snapshots anchor vertex data
///      (fast byte copy), dispatches all heavy computation to a background
///      thread, and returns immediately — render loop is never blocked.
///   5. Background thread computes per-vertex heat colors + label positions.
///   6. `renderer(_:updateAtTime:)` Phase 2 (next frame): applies pre-computed
///      results — rebuilds geometry and adds floating text labels per anchor.
///   7. Subsequent `renderer(_:didUpdate:)` calls rebuild with heat colors as
///      ARKit refines the mesh (labels not recreated — stable reference points).
///   8. User taps Reset → `resetTrigger` increments → coordinator clears
///      `_heatmapActive` so new nodes revert to white on next scan pass.
public final class ARMeshCoordinator: NSObject, ARSCNViewDelegate {

    // MARK: Shared state (lock required)

    private let lock = NSLock()
    private var _isRescan: Bool = false
    private var _spatialHash: SpatialHashGrid? = nil
    private var _targetMM: Float = 40
    private var _tolMM: Float = 2
    private var _alignmentTransform: simd_float4x4 = .identity
    private var _originalBoundsMin: SIMD3<Float> = SIMD3<Float>(repeating: -1000)
    private var _originalBoundsMax: SIMD3<Float> = SIMD3<Float>(repeating:  1000)
    private var _heatmapActive: Bool = false
    private var _heatmapRequested: Bool = false
    private var _lastResetTrigger: Int = 0
    private var _measurementUnit: MeasurementUnit = .centimeters
    private var _projectType: ProjectType = .plaster
    /// True while background heatmap computation is in flight.
    private var _heatmapComputing: Bool = false
    /// Pre-computed per-anchor results waiting to be applied on the render thread.
    private var _pendingHeatmapResults: [PendingAnchorResult]? = nil

    // MARK: Init

    init(mode: ScanVisualizationMode) {
        super.init()
        applyMode(mode)
    }

    func setMode(_ mode: ScanVisualizationMode) {
        applyMode(mode)
    }

    /// Called from `updateUIView` (main thread). Handles heatmap request and reset.
    func handleHeatmap(requested: Bool, resetTrigger: Int) {
        lock.lock()
        if resetTrigger != _lastResetTrigger {
            _lastResetTrigger = resetTrigger
            _heatmapActive = false
            _heatmapRequested = false
            _heatmapComputing = false
            _pendingHeatmapResults = nil
        }
        if requested, _isRescan, !_heatmapActive, _spatialHash != nil {
            _heatmapRequested = true
        }
        lock.unlock()
    }

    /// Called from `updateUIView` (main thread). Updates display formatting config.
    func setDisplayConfig(unit: MeasurementUnit, projectType: ProjectType) {
        lock.lock()
        _measurementUnit = unit
        _projectType = projectType
        lock.unlock()
    }

    private func applyMode(_ mode: ScanVisualizationMode) {
        switch mode {
        case .original:
            lock.lock()
            _isRescan = false
            _spatialHash = nil
            _alignmentTransform = .identity
            _originalBoundsMin = SIMD3<Float>(repeating: -1000)
            _originalBoundsMax = SIMD3<Float>(repeating:  1000)
            _heatmapActive = false
            _heatmapRequested = false
            _heatmapComputing = false
            _pendingHeatmapResults = nil
            lock.unlock()

        case .rescan(let mesh, let alignTx, let target, let tol):
            lock.lock()
            _isRescan = true
            _targetMM = target
            _tolMM = tol
            _alignmentTransform = alignTx
            let alreadyBuilt = _spatialHash != nil
            lock.unlock()

            guard !alreadyBuilt else { return }
            let vertices = mesh.vertices
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let grid = SpatialHashGrid(points: vertices, cellSize: 0.05)
                var bMin = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
                var bMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
                for v in vertices { bMin = simd_min(bMin, v); bMax = simd_max(bMax, v) }
                self.lock.lock()
                self._spatialHash = grid
                self._originalBoundsMin = bMin
                self._originalBoundsMax = bMax
                self.lock.unlock()
            }
        }
    }

    // MARK: - Render-thread-only caches (no lock — only touched on render thread)

    private var faceElementCache: [UUID: (faceCount: Int, element: SCNGeometryElement)] = [:]

    // MARK: - Cached materials

    private lazy var plainMeshMaterial: SCNMaterial = {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 1, alpha: 0.40)
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        mat.lightingModel = .constant
        return mat
    }()

    private lazy var heatmapMaterial: SCNMaterial = {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.white
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        mat.lightingModel = .constant
        return mat
    }()

    // MARK: - ARSCNViewDelegate

    public func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
        let node = SCNNode()
        let vc = meshAnchor.geometry.vertices.count
        let fc = meshAnchor.geometry.faces.count
        // New anchors created after heatmap is frozen always start white — they
        // were not present during the one-shot color pass and the alignment
        // transform may have drifted since then.
        node.geometry = buildGeometry(for: meshAnchor, vertexCount: vc, useColors: false)
        node.setValue(vc, forKeyPath: "vc")
        node.setValue(fc, forKeyPath: "fc")
        return node
    }

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let newVC = meshAnchor.geometry.vertices.count
        let newFC = meshAnchor.geometry.faces.count
        let oldVC = node.value(forKeyPath: "vc") as? Int ?? -1
        let oldFC = node.value(forKeyPath: "fc") as? Int ?? -1

        lock.lock()
        let isRescan = _isRescan
        let heatmapActive = _heatmapActive
        lock.unlock()

        if isRescan {
            if newVC == oldVC { return }
        } else {
            if newVC == oldVC && newFC == oldFC { return }
        }

        // ARKit updates the Metal buffer in-place when it refines an anchor.
        // The SCNGeometry must be rebuilt so the color source aligns with the
        // new vertex layout — skipping this causes colours to map onto the
        // wrong triangles (the "all wrong colours" bug).
        node.geometry = buildGeometry(for: meshAnchor, vertexCount: newVC, useColors: isRescan && heatmapActive)
        node.setValue(newVC, forKeyPath: "vc")
        node.setValue(newFC, forKeyPath: "fc")
    }

    public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        faceElementCache.removeValue(forKey: anchor.identifier)
    }

    /// Two-phase heatmap pass. Phase 1 (first call with request armed): snapshots
    /// anchor vertex data and dispatches all heavy work to a background thread —
    /// returns immediately, never blocking the render loop. Phase 2 (subsequent
    /// call): applies the pre-computed results to the scene nodes.
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {

        // Phase 2: apply results that the background thread finished computing.
        lock.lock()
        if let pending = _pendingHeatmapResults {
            _pendingHeatmapResults = nil
            _heatmapComputing = false
            lock.unlock()
            applyPendingHeatmap(pending, renderer: renderer)
            return
        }

        // Phase 1: arm the background computation on the first frame after request.
        guard _heatmapRequested, _isRescan, !_heatmapComputing else {
            lock.unlock(); return
        }
        _heatmapRequested = false
        _heatmapActive = true
        _heatmapComputing = true

        let hash      = _spatialHash          // SpatialHashGrid is a struct — captured as a copy
        let target    = _targetMM
        let tol       = _tolMM
        let alignTx   = _alignmentTransform
        let boundsMin = _originalBoundsMin - Float(1.0)
        let boundsMax = _originalBoundsMax + Float(1.0)
        let unit      = _measurementUnit
        lock.unlock()

        guard let arView = renderer as? ARSCNView else { return }

        // Copy vertex bytes out of ARKit's Metal buffers before leaving the render
        // thread. ARKit may update buffers in-place between frames, so we must
        // snapshot them now rather than hold raw pointers across thread boundaries.
        var snapshots: [AnchorSnapshot] = []
        for anchor in arView.session.currentFrame?.anchors ?? [] {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            let g = mesh.geometry
            let vc = g.vertices.count
            guard vc > 0 else { continue }
            let stride  = g.vertices.stride
            let byteLen = vc * stride
            let data = Data(bytes: g.vertices.buffer.contents().advanced(by: g.vertices.offset), count: byteLen)
            snapshots.append(AnchorSnapshot(
                id: mesh.identifier, vc: vc, fc: g.faces.count,
                vertexData: data, stride: stride, transform: mesh.transform))
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var results: [PendingAnchorResult] = []
            for snap in snapshots {
                let colors = self.computeColorsBackground(
                    vertexData: snap.vertexData, stride: snap.stride, vertexCount: snap.vc,
                    transform: snap.transform, hash: hash, target: target, tol: tol,
                    alignTx: alignTx, boundsMin: boundsMin, boundsMax: boundsMax)

                let stats = self.computeStatsBackground(
                    vertexData: snap.vertexData, stride: snap.stride, vertexCount: snap.vc,
                    transform: snap.transform, hash: hash, alignTx: alignTx,
                    boundsMin: boundsMin, boundsMax: boundsMax)

                var labelNode: SCNNode? = nil
                if stats.sampleCount >= 1 {
                    let centroid = stats.outOfRangeCount >= 1 ? stats.outOfRangeCentroid : stats.centroid
                    let distMM   = stats.outOfRangeCount >= 1 ? stats.outOfRangeAvgDistMM : stats.avgDistMM
                    labelNode = self.buildLabelNode(avgDistMM: distMM, centroid: centroid, unit: unit)
                }

                results.append(PendingAnchorResult(
                    anchorID: snap.id, vertexCount: snap.vc, faceCount: snap.fc,
                    colorData: colors, labelNode: labelNode))
            }
            self.lock.lock()
            // Discard if a reset happened while we were computing.
            if self._heatmapComputing {
                self._pendingHeatmapResults = results
            }
            self.lock.unlock()
        }
    }

    // MARK: - Apply phase (render thread)

    private func applyPendingHeatmap(_ pending: [PendingAnchorResult], renderer: SCNSceneRenderer) {
        guard let arView = renderer as? ARSCNView else { return }
        for result in pending {
            guard
                let anchor = arView.session.currentFrame?.anchors
                    .first(where: { $0.identifier == result.anchorID }) as? ARMeshAnchor,
                let node = arView.node(for: anchor)
            else { continue }

            // Apply geometry only when vertex count still matches — stale color data
            // would misalign colors to vertices. didUpdate will recolor refined anchors.
            if anchor.geometry.vertices.count == result.vertexCount {
                node.geometry = buildGeometryWithPrecomputedColors(
                    for: anchor, vertexCount: result.vertexCount, colorData: result.colorData)
                node.setValue(result.vertexCount, forKeyPath: "vc")
                node.setValue(result.faceCount,   forKeyPath: "fc")
            }

            // Always apply label — centroid is approximately correct even for anchors
            // that were slightly refined during the background computation window.
            if let labelNode = result.labelNode {
                node.childNodes
                    .filter { $0.name == "heatmap_label" }
                    .forEach { $0.removeFromParentNode() }
                node.addChildNode(labelNode)
            }
        }
    }

    // MARK: - Background computation types

    private struct AnchorSnapshot {
        let id: UUID; let vc: Int; let fc: Int
        let vertexData: Data; let stride: Int; let transform: simd_float4x4
    }

    private struct PendingAnchorResult {
        let anchorID: UUID
        let vertexCount: Int
        let faceCount: Int
        let colorData: [Float]
        let labelNode: SCNNode?
    }

    /// Statistics computed from a sampled subset of vertices for label placement.
    private struct MeshAnchorStats {
        let sampleCount: Int
        let avgDistMM: Float
        let centroid: SIMD3<Float>
        let outOfRangeCount: Int
        let outOfRangeAvgDistMM: Float
        let outOfRangeCentroid: SIMD3<Float>
    }

    // MARK: - Background computation helpers

    /// Computes per-vertex RGBA heat colors from a snapshot of vertex bytes.
    /// Safe to call from any thread — operates on a copied Data buffer.
    private func computeColorsBackground(
        vertexData: Data, stride: Int, vertexCount: Int,
        transform: simd_float4x4, hash: SpatialHashGrid?,
        target: Float, tol: Float, alignTx: simd_float4x4,
        boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>
    ) -> [Float] {
        var rgba = [Float](repeating: 0, count: vertexCount * 4)
        vertexData.withUnsafeBytes { rawBuf in
            guard let basePtr = rawBuf.baseAddress else { return }
            for i in 0..<vertexCount {
                var local = SIMD3<Float>()
                withUnsafeMutableBytes(of: &local) { dst in
                    dst.copyBytes(from: UnsafeRawBufferPointer(
                        start: basePtr.advanced(by: i * stride), count: 12))
                }
                let world    = transform.transformPoint(local)
                let queryPos = alignTx.transformPoint(world)
                let r, g, b, a: Float
                let inBounds = queryPos.x >= boundsMin.x && queryPos.x <= boundsMax.x
                            && queryPos.y >= boundsMin.y && queryPos.y <= boundsMax.y
                            && queryPos.z >= boundsMin.z && queryPos.z <= boundsMax.z
                if inBounds, let h = hash {
                    if let match = h.nearestNeighbor(to: queryPos, maxRadius: 0.15) {
                        let distMM = sqrt(match.distanceSquared) * 1000
                        (r, g, b, a) = heatColor(distMM, target: target, tol: tol)
                    } else {
                        (r, g, b, a) = (0.95, 0.12, 0.12, 0.75)  // red — beyond 15 cm range
                    }
                } else {
                    (r, g, b, a) = (0.30, 0.30, 0.30, 0.35)      // outside scan area — dim
                }
                let base = i * 4
                rgba[base] = r; rgba[base + 1] = g; rgba[base + 2] = b; rgba[base + 3] = a
            }
        }
        return rgba
    }

    /// Samples up to 600 vertices to find centroids for in-range and out-of-range
    /// color zones, so labels land on the correct coloured region.
    /// Safe to call from any thread — operates on a copied Data buffer.
    private func computeStatsBackground(
        vertexData: Data, stride: Int, vertexCount: Int,
        transform: simd_float4x4, hash: SpatialHashGrid?,
        alignTx: simd_float4x4, boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>
    ) -> MeshAnchorStats {
        let step = max(1, vertexCount / 600)
        var centroidSum = SIMD3<Float>.zero, totalDist: Float = 0, count = 0
        var oorCentroidSum = SIMD3<Float>.zero, oorTotalDist: Float = 0, oorCount = 0

        vertexData.withUnsafeBytes { rawBuf in
            guard let basePtr = rawBuf.baseAddress else { return }
            var i = 0
            while i < vertexCount {
                var local = SIMD3<Float>()
                withUnsafeMutableBytes(of: &local) { dst in
                    dst.copyBytes(from: UnsafeRawBufferPointer(
                        start: basePtr.advanced(by: i * stride), count: 12))
                }
                let world    = transform.transformPoint(local)
                let queryPos = alignTx.transformPoint(world)
                let inBounds = queryPos.x >= boundsMin.x && queryPos.x <= boundsMax.x
                            && queryPos.y >= boundsMin.y && queryPos.y <= boundsMax.y
                            && queryPos.z >= boundsMin.z && queryPos.z <= boundsMax.z
                if inBounds, let h = hash, let match = h.nearestNeighbor(to: queryPos, maxRadius: 1.0) {
                    let distM  = sqrt(match.distanceSquared)
                    let distMM = distM * 1000
                    centroidSum += local; totalDist += distMM; count += 1
                    if distM > 0.15 { oorCentroidSum += local; oorTotalDist += distMM; oorCount += 1 }
                }
                i += step
            }
        }
        return MeshAnchorStats(
            sampleCount: count,
            avgDistMM: count > 0 ? totalDist / Float(count) : 0,
            centroid: count > 0 ? centroidSum / Float(count) : .zero,
            outOfRangeCount: oorCount,
            outOfRangeAvgDistMM: oorCount > 0 ? oorTotalDist / Float(oorCount) : 0,
            outOfRangeCentroid: oorCount > 0 ? oorCentroidSum / Float(oorCount) : .zero)
    }

    // MARK: - Geometry construction

    private func buildGeometry(for anchor: ARMeshAnchor, vertexCount: Int, useColors: Bool) -> SCNGeometry {
        let arGeom = anchor.geometry

        let vertexSrc = SCNGeometrySource(
            buffer: arGeom.vertices.buffer,
            vertexFormat: arGeom.vertices.format,
            semantic: .vertex,
            vertexCount: vertexCount,
            dataOffset: arGeom.vertices.offset,
            dataStride: arGeom.vertices.stride
        )
        let normalSrc = SCNGeometrySource(
            buffer: arGeom.normals.buffer,
            vertexFormat: arGeom.normals.format,
            semantic: .normal,
            vertexCount: arGeom.normals.count,
            dataOffset: arGeom.normals.offset,
            dataStride: arGeom.normals.stride
        )
        let faceCount = arGeom.faces.count
        let faceElement: SCNGeometryElement
        if let cached = faceElementCache[anchor.identifier], cached.faceCount == faceCount {
            faceElement = cached.element
        } else {
            let faceData = Data(bytes: arGeom.faces.buffer.contents(), count: arGeom.faces.buffer.length)
            let elem = SCNGeometryElement(
                data: faceData,
                primitiveType: .triangles,
                primitiveCount: faceCount,
                bytesPerIndex: arGeom.faces.bytesPerIndex
            )
            faceElementCache[anchor.identifier] = (faceCount: faceCount, element: elem)
            faceElement = elem
        }

        if !useColors {
            let geom = SCNGeometry(sources: [vertexSrc, normalSrc], elements: [faceElement])
            geom.firstMaterial = plainMeshMaterial
            return geom
        }

        let colorSrc = buildColorSource(arGeom: arGeom, transform: anchor.transform, vertexCount: vertexCount)
        let geom = SCNGeometry(sources: [vertexSrc, normalSrc, colorSrc], elements: [faceElement])
        geom.firstMaterial = heatmapMaterial
        return geom
    }

    /// Builds geometry using pre-computed color data — avoids re-running hash queries
    /// on the render thread when applying background heatmap results.
    private func buildGeometryWithPrecomputedColors(
        for anchor: ARMeshAnchor,
        vertexCount: Int,
        colorData: [Float]
    ) -> SCNGeometry {
        let arGeom = anchor.geometry
        let vertexSrc = SCNGeometrySource(
            buffer: arGeom.vertices.buffer, vertexFormat: arGeom.vertices.format,
            semantic: .vertex, vertexCount: vertexCount,
            dataOffset: arGeom.vertices.offset, dataStride: arGeom.vertices.stride)
        let normalSrc = SCNGeometrySource(
            buffer: arGeom.normals.buffer, vertexFormat: arGeom.normals.format,
            semantic: .normal, vertexCount: arGeom.normals.count,
            dataOffset: arGeom.normals.offset, dataStride: arGeom.normals.stride)
        let faceCount = arGeom.faces.count
        let faceElement: SCNGeometryElement
        if let cached = faceElementCache[anchor.identifier], cached.faceCount == faceCount {
            faceElement = cached.element
        } else {
            let faceData = Data(bytes: arGeom.faces.buffer.contents(), count: arGeom.faces.buffer.length)
            let elem = SCNGeometryElement(
                data: faceData, primitiveType: .triangles,
                primitiveCount: faceCount, bytesPerIndex: arGeom.faces.bytesPerIndex)
            faceElementCache[anchor.identifier] = (faceCount: faceCount, element: elem)
            faceElement = elem
        }
        let colorSrc = SCNGeometrySource(
            data: colorData.withUnsafeBytes { Data($0) },
            semantic: .color, vectorCount: vertexCount, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4)
        let geom = SCNGeometry(sources: [vertexSrc, normalSrc, colorSrc], elements: [faceElement])
        geom.firstMaterial = heatmapMaterial
        return geom
    }

    /// Builds a per-vertex color source by querying the spatial hash. Called from
    /// `renderer(_:didUpdate:)` on the render thread for individual anchor refreshes
    /// (not the initial bulk pass — that uses `computeColorsBackground`).
    private func buildColorSource(
        arGeom: ARMeshGeometry,
        transform: simd_float4x4,
        vertexCount: Int
    ) -> SCNGeometrySource {
        lock.lock()
        let hash      = _spatialHash
        let target    = _targetMM
        let tol       = _tolMM
        let alignTx   = _alignmentTransform
        let boundsMin = _originalBoundsMin - Float(1.0)
        let boundsMax = _originalBoundsMax + Float(1.0)
        lock.unlock()

        let stride     = arGeom.vertices.stride
        let dataOffset = arGeom.vertices.offset
        let basePtr    = arGeom.vertices.buffer.contents().advanced(by: dataOffset)

        var rgba = [Float](repeating: 0, count: vertexCount * 4)
        for i in 0..<vertexCount {
            let ptr = basePtr.advanced(by: i * stride)
            var local = SIMD3<Float>()
            withUnsafeMutableBytes(of: &local) { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(start: ptr, count: 12))
            }
            let world    = transform.transformPoint(local)
            let queryPos = alignTx.transformPoint(world)

            let r, g, b, a: Float
            let inBounds = queryPos.x >= boundsMin.x && queryPos.x <= boundsMax.x
                        && queryPos.y >= boundsMin.y && queryPos.y <= boundsMax.y
                        && queryPos.z >= boundsMin.z && queryPos.z <= boundsMax.z
            if inBounds, let h = hash {
                if let match = h.nearestNeighbor(to: queryPos, maxRadius: 0.15) {
                    let distMM = sqrt(match.distanceSquared) * 1000
                    (r, g, b, a) = heatColor(distMM, target: target, tol: tol)
                } else {
                    (r, g, b, a) = (0.95, 0.12, 0.12, 0.75)
                }
            } else {
                (r, g, b, a) = (0.30, 0.30, 0.30, 0.35)
            }
            let base = i * 4
            rgba[base] = r; rgba[base + 1] = g; rgba[base + 2] = b; rgba[base + 3] = a
        }

        return SCNGeometrySource(
            data: rgba.withUnsafeBytes { Data($0) },
            semantic: .color,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
    }

    // MARK: - AR Text labels

    /// Creates a floating billboard label badge (dark pill + white text). Called from
    /// the background computation thread — UIFont, UIColor, SCNText, SCNPlane, and
    /// SCNNode are all safe to create off the main/render thread.
    ///
    /// The returned node is a container positioned at `centroid` in anchor-local space.
    /// Its `SCNBillboardConstraint` (freeAxes = .all) keeps it facing the camera.
    /// Children are in the container's billboard-rotated local space: +Z toward camera,
    /// so text (z=0) renders in front of the background (z=-0.001).
    private func buildLabelNode(avgDistMM: Float, centroid: SIMD3<Float>, unit: MeasurementUnit) -> SCNNode {
        let labelStr = formatDistMM(avgDistMM, unit: unit)
        let scale: Float = 0.025  // 2.5 cm text height at typical 1–2 m scanning distance

        // ── Text geometry ──────────────────────────────────────────────────────────
        let text = SCNText(string: labelStr, extrusionDepth: 0)
        text.font = UIFont.boldSystemFont(ofSize: 1)  // 1 unit = 1 m; scaled by `scale`
        text.flatness = 0.2
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.isDoubleSided = true
        text.firstMaterial?.lightingModel = .constant
        // Disable depth testing so the label is never occluded by mesh geometry.
        text.firstMaterial?.writesToDepthBuffer = false
        text.firstMaterial?.readsFromDepthBuffer = false

        // Measure text in world-space units (bounding box is in text-local units × scale).
        let bbox       = text.boundingBox                           // triggers tessellation here, off render thread
        let textWidth  = (bbox.max.x - bbox.min.x) * scale
        let textHeight = (bbox.max.y - bbox.min.y) * scale
        let halfWidth  = textWidth / 2

        let textNode = SCNNode(geometry: text)
        textNode.scale = SCNVector3(scale, scale, scale)
        // Center horizontally; Y=0 is the text baseline inside the container.
        textNode.position = SCNVector3(-halfWidth, 0, 0)
        textNode.renderingOrder = 2

        // ── Background pill ────────────────────────────────────────────────────────
        let padX: Float = 0.006
        let padY: Float = 0.005
        let bgW = CGFloat(textWidth  + padX * 2)
        let bgH = CGFloat(textHeight + padY * 2)
        let bg  = SCNPlane(width: bgW, height: bgH)
        bg.cornerRadius = bgH / 2
        bg.firstMaterial?.diffuse.contents = UIColor(white: 0.0, alpha: 0.72)
        bg.firstMaterial?.lightingModel    = .constant
        bg.firstMaterial?.isDoubleSided    = true
        bg.firstMaterial?.writesToDepthBuffer  = false
        bg.firstMaterial?.readsFromDepthBuffer = false

        let bgNode = SCNNode(geometry: bg)
        // Center the pill on the text: text spans [0, textWidth] × [0, textHeight]
        // in container space; pill center is at (0, textHeight/2).
        bgNode.position = SCNVector3(0, textHeight / 2, -0.001)  // 1 mm behind text
        bgNode.renderingOrder = 1

        // ── Container ──────────────────────────────────────────────────────────────
        let containerNode = SCNNode()
        containerNode.name = "heatmap_label"
        containerNode.position = SCNVector3(centroid.x, centroid.y + textHeight / 2, centroid.z)
        containerNode.addChildNode(bgNode)
        containerNode.addChildNode(textNode)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        containerNode.constraints = [billboard]

        return containerNode
    }

    private func formatDistMM(_ mm: Float, unit: MeasurementUnit) -> String {
        let value = Float(unit.fromMillimeters(Double(mm)))
        switch unit {
        case .millimeters: return String(format: "%.0fmm", value)
        case .centimeters: return String(format: "%.1fcm", value)
        case .inches:      return String(format: "%.2fin", value)
        }
    }

    // MARK: - Heat color

    private func heatColor(_ mm: Float, target: Float, tol: Float) -> (Float, Float, Float, Float) {
        let a: Float = 0.75
        if mm > target + tol * 2  { return (0.95, 0.12, 0.12, a) }  // red    — way over
        if mm > target + tol      { return (0.95, 0.52, 0.10, a) }  // orange — slightly over
        if mm >= target - tol     { return (0.14, 0.88, 0.30, a) }  // green  — perfect
        if mm >= target - tol * 2 { return (0.92, 0.88, 0.12, a) }  // yellow — slightly thin
        return                              (0.14, 0.38, 0.95, a)   // blue   — bare / not yet done
    }
}
