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
///   4. `renderer(_:updateAtTime:)` fires once: sets `_heatmapActive`, rebuilds
///      all nodes with heat colors, adds floating AR text labels per anchor.
///   5. Subsequent `renderer(_:didUpdate:)` calls rebuild with heat colors as
///      ARKit refines the mesh (labels not recreated — stable reference points).
///   6. User taps Reset → `resetTrigger` increments → coordinator clears
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
        lock.lock()
        let useColors = _isRescan && _heatmapActive
        lock.unlock()
        node.geometry = buildGeometry(for: meshAnchor, vertexCount: vc, useColors: useColors)
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

        // In rescan mode with heatmap active, update geometry with new colors.
        // Do NOT recreate text labels here — they stay as stable reference points.
        node.geometry = buildGeometry(for: meshAnchor, vertexCount: newVC, useColors: isRescan && heatmapActive)
        node.setValue(newVC, forKeyPath: "vc")
        node.setValue(newFC, forKeyPath: "fc")
    }

    public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        faceElementCache.removeValue(forKey: anchor.identifier)
    }

    /// One-shot heatmap pass: sets `_heatmapActive`, rebuilds all existing anchor
    /// nodes with heat colors, and adds a floating AR text label per anchor showing
    /// the average measured distance for that region.
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        guard _heatmapRequested, _isRescan else { lock.unlock(); return }
        _heatmapRequested = false
        _heatmapActive = true
        lock.unlock()

        guard let arView = renderer as? ARSCNView else { return }
        for anchor in arView.session.currentFrame?.anchors ?? [] {
            guard let meshAnchor = anchor as? ARMeshAnchor,
                  let node = arView.node(for: anchor) else { continue }
            let vc = meshAnchor.geometry.vertices.count
            let fc = meshAnchor.geometry.faces.count
            node.geometry = buildGeometry(for: meshAnchor, vertexCount: vc, useColors: true)
            node.setValue(vc, forKeyPath: "vc")
            node.setValue(fc, forKeyPath: "fc")

            // Add floating distance label at the anchor's mesh centroid.
            let stats = computeMeshStats(arGeom: meshAnchor.geometry, transform: meshAnchor.transform, vertexCount: vc)
            if stats.matchCount >= 5, stats.avgDistMM > 2.0 {
                addLabelNode(to: node, avgDistMM: stats.avgDistMM, centroid: stats.centroid)
            }
        }
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

    private func buildColorSource(
        arGeom: ARMeshGeometry,
        transform: simd_float4x4,
        vertexCount: Int
    ) -> SCNGeometrySource {
        lock.lock()
        let hash = _spatialHash
        let target = _targetMM
        let tol = _tolMM
        let alignTx = _alignmentTransform
        let boundsMin = _originalBoundsMin - Float(0.15)
        let boundsMax = _originalBoundsMax + Float(0.15)
        lock.unlock()

        let stride = arGeom.vertices.stride
        let dataOffset = arGeom.vertices.offset
        let basePtr = arGeom.vertices.buffer.contents().advanced(by: dataOffset)

        var rgba = [Float](repeating: 0, count: vertexCount * 4)
        for i in 0..<vertexCount {
            let ptr = basePtr.advanced(by: i * stride)
            var local = SIMD3<Float>()
            withUnsafeMutableBytes(of: &local) { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(start: ptr, count: 12))
            }
            let world = transform.transformPoint(local)
            let queryPos = alignTx.transformPoint(world)

            let r, g, b, a: Float
            let inBounds = queryPos.x >= boundsMin.x && queryPos.x <= boundsMax.x
                        && queryPos.y >= boundsMin.y && queryPos.y <= boundsMax.y
                        && queryPos.z >= boundsMin.z && queryPos.z <= boundsMax.z
            if inBounds, let h = hash, let match = h.nearestNeighbor(to: queryPos, maxRadius: 0.15) {
                let distMM = sqrt(match.distanceSquared) * 1000
                (r, g, b, a) = heatColor(distMM, target: target, tol: tol)
            } else {
                (r, g, b, a) = (0.55, 0.55, 0.55, 0.60)
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

    /// Statistics computed from a sampled subset of vertices for label placement.
    private struct MeshAnchorStats {
        let matchCount: Int
        let avgDistMM: Float
        let centroid: SIMD3<Float>  // anchor-local space
    }

    /// Samples up to 200 vertices to compute average distance and centroid for
    /// the label. Cheap compared to buildColorSource (no RGBA array allocation).
    private func computeMeshStats(arGeom: ARMeshGeometry, transform: simd_float4x4, vertexCount: Int) -> MeshAnchorStats {
        lock.lock()
        let hash = _spatialHash
        let alignTx = _alignmentTransform
        let boundsMin = _originalBoundsMin - Float(0.15)
        let boundsMax = _originalBoundsMax + Float(0.15)
        lock.unlock()

        let stride = arGeom.vertices.stride
        let dataOffset = arGeom.vertices.offset
        let basePtr = arGeom.vertices.buffer.contents().advanced(by: dataOffset)
        let step = max(1, vertexCount / 200)

        var centroidSum = SIMD3<Float>.zero
        var totalDist: Float = 0
        var count = 0
        var i = 0
        while i < vertexCount {
            let ptr = basePtr.advanced(by: i * stride)
            var local = SIMD3<Float>()
            withUnsafeMutableBytes(of: &local) { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(start: ptr, count: 12))
            }
            let world = transform.transformPoint(local)
            let queryPos = alignTx.transformPoint(world)
            let inBounds = queryPos.x >= boundsMin.x && queryPos.x <= boundsMax.x
                        && queryPos.y >= boundsMin.y && queryPos.y <= boundsMax.y
                        && queryPos.z >= boundsMin.z && queryPos.z <= boundsMax.z
            if inBounds, let h = hash, let match = h.nearestNeighbor(to: queryPos, maxRadius: 0.15) {
                centroidSum += local
                totalDist += sqrt(match.distanceSquared) * 1000
                count += 1
            }
            i += step
        }
        return MeshAnchorStats(
            matchCount: count,
            avgDistMM: count > 0 ? totalDist / Float(count) : 0,
            centroid: count > 0 ? centroidSum / Float(count) : .zero
        )
    }

    /// Creates (or replaces) a floating billboard text node as a child of `parentNode`.
    private func addLabelNode(to parentNode: SCNNode, avgDistMM: Float, centroid: SIMD3<Float>) {
        // Remove stale label if present.
        parentNode.childNodes
            .filter { $0.name == "heatmap_label" }
            .forEach { $0.removeFromParentNode() }

        lock.lock()
        let unit = _measurementUnit
        lock.unlock()

        let labelStr = formatDistMM(avgDistMM, unit: unit)

        let text = SCNText(string: labelStr, extrusionDepth: 0)
        text.font = UIFont.boldSystemFont(ofSize: 1)  // 1 unit = 1 m; we scale down
        text.flatness = 0.2
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.isDoubleSided = true
        text.firstMaterial?.lightingModel = .constant

        let textNode = SCNNode(geometry: text)
        textNode.name = "heatmap_label"

        // 3 cm text height at typical scanning distance (1–2 m).
        let scale: Float = 0.03
        textNode.scale = SCNVector3(scale, scale, scale)

        // Center the text: compute bounding box width in local units, then shift left
        // by half so the label centers on the centroid rather than starting from it.
        let bbox = text.boundingBox
        let halfWidth = ((bbox.max.x - bbox.min.x) * scale) / 2
        textNode.position = SCNVector3(centroid.x - halfWidth, centroid.y, centroid.z)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]

        parentNode.addChildNode(textNode)
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
