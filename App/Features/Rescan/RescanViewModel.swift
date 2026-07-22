import Foundation
import SwiftUI
import ARKit
import Combine
import simd
import ScanArtAR
import ScanArtAlgorithms
import ScanArtCore
import ScanArtPersistence

@MainActor
final class RescanViewModel: ObservableObject {
    let projectID: UUID
    let sessionManager = ARScanSessionManager()

    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false
    @Published var savedScanID: UUID?
    @Published private(set) var originalMesh: MeshBuffer?
    /// Maps current-session world coordinates → original-session frame.
    /// Starts as identity; updated once background ICP on stable reference faces
    /// (floor/ceiling/doors) converges.
    @Published private(set) var alignmentTransform: simd_float4x4 = .identity
    /// Approximate plaster volume in litres. Nil until the user taps "Calculate".
    @Published private(set) var estimatedVolumeLiters: Double?
    @Published private(set) var isComputingVolume = false

    /// True once the user has tapped "Generate Heatmap". Passed to ARCameraView
    /// to arm the one-shot color pass on the render thread.
    @Published private(set) var heatmapRequested = false
    /// True once heatmap has been requested. Drives UI state (button → indicator,
    /// legend visibility, Colors stat card label).
    @Published private(set) var heatmapGenerated = false
    /// Incrementing counter passed to ARCameraView. Each increment clears the
    /// coordinator's heatmap state so a fresh rescan starts with a white mesh.
    @Published private(set) var resetTrigger = 0

    private(set) var targetThicknessMM: Float = 40
    private(set) var toleranceMM: Float = 2
    @Published private(set) var projectType: ProjectType = .plaster
    private(set) var measurementUnit: MeasurementUnit = .centimeters

    private let di: DIContainer
    private let folderManager: ProjectFolderManager?
    private var originalScan: ScanRecord?
    private var sessionManagerSubscription: AnyCancellable?
    /// Nonce used to cancel stale alignment tasks when the session is reset.
    /// A pending task compares its captured nonce against the current one;
    /// if they differ the task exits without writing `alignmentTransform`.
    private var alignmentNonce = UUID()

    init(projectID: UUID, di: DIContainer) {
        self.projectID = projectID
        self.di = di
        self.folderManager = try? ProjectFolderManager()
        self.sessionManagerSubscription = sessionManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        guard let project = try? di.projectRepository.fetchProject(id: projectID),
              let original = project.originalScan else {
            errorMessage = "This project doesn't have an original scan yet."
            return
        }
        originalScan = original
        targetThicknessMM = Float(project.desiredThicknessMM)
        toleranceMM = Float(project.toleranceMM)
        projectType = project.projectType
        measurementUnit = project.unit

        // Always run a completely fresh scan — no world map, no relocalization.
        // Using initialWorldMap puts ARKit into a relocalization-only mode that
        // BLOCKS new mesh anchor generation until visual re-localization succeeds.
        // With small original scans (few anchor features) that never happens, so
        // the session stays stuck at "Finding position" with 0 % coverage.
        //
        // Instead: scan immediately, colour the live mesh via nearest-neighbour
        // proximity against the original mesh (works well when the user stands in
        // roughly the same spot), and run ICP alignment at save time for the
        // precise stored result.
        sessionManager.startOriginalScan()

        // Load the original mesh in the background for the on-demand heat-map.
        let meshName = original.meshFileName
        let pid = projectID
        Task { [weak self] in
            guard let self, let fm = self.folderManager,
                  let folder = try? fm.meshesFolder(for: pid) else { return }
            let url = folder.appendingPathComponent(meshName)
            let loadTask = Task.detached(priority: .userInitiated) { try MeshFileStorage.loadMesh(from: url) }
            guard let loaded = try? await loadTask.value else { return }
            self.originalMesh = loaded
            self.scheduleAlignment(originalMesh: loaded)
        }
    }

    func stop() {
        sessionManager.pause()
    }

    // MARK: - Heatmap

    /// Arms the heatmap pass in ARCameraView. The coordinator will color all
    /// current mesh nodes on the next render frame; subsequent `didUpdate` calls
    /// will also use heat colors as ARKit refines the mesh.
    func generateHeatmap() {
        guard originalMesh != nil else { return }
        heatmapRequested = true
        heatmapGenerated = true
    }

    // MARK: - Reset

    /// Restarts the rescan session from scratch: clears heatmap state, resets
    /// all live measurements, and starts a fresh ARKit scan. The original mesh
    /// (loaded from disk) is retained — no need to reload it.
    func resetScan() {
        // Invalidate any pending alignment task.
        alignmentNonce = UUID()

        heatmapRequested = false
        heatmapGenerated = false
        estimatedVolumeLiters = nil
        isComputingVolume = false
        alignmentTransform = .identity
        // Incrementing this tells the coordinator to clear _heatmapActive so
        // new mesh nodes start as white again.
        resetTrigger += 1

        sessionManager.stop()
        sessionManager.startOriginalScan()

        if let mesh = originalMesh {
            scheduleAlignment(originalMesh: mesh)
        }
    }

    // MARK: - Volume

    /// One-shot volume estimate triggered by the user. Builds a spatial hash from
    /// the current rescan mesh, projects each original-mesh vertex along its normal
    /// to get a signed thickness, then sums only samples at or above the green band.
    func computeVolumeOnce() {
        guard !isComputingVolume, let origMesh = originalMesh else { return }
        isComputingVolume = true
        let rescanMesh = sessionManager.currentMeshBuffer()
        let isExcavation = projectType == .excavation
        let minimumMM = Float(max(0, Double(targetThicknessMM) - Double(toleranceMM)))
        Task { [weak self] in
            let liters = await Task.detached(priority: .userInitiated) {
                guard !rescanMesh.vertices.isEmpty else { return 0.0 }
                let hash = SpatialHashGrid(points: rescanMesh.vertices, cellSize: 0.05)
                let areas = SurfaceAreaCalculator.vertexAreas(origMesh)
                var total = 0.0
                for i in 0..<origMesh.vertices.count {
                    guard let m = hash.nearestNeighbor(to: origMesh.vertices[i], maxRadius: 0.15) else { continue }
                    let rescanV = rescanMesh.vertices[Int(m.index)]
                    let n = origMesh.normals[i]
                    let signedMM = simd_dot(rescanV - origMesh.vertices[i], n) * 1000
                    if isExcavation {
                        guard signedMM <= -minimumMM else { continue }
                        total += Double(-signedMM) / 1000.0 * Double(areas[i])
                    } else {
                        guard signedMM >= minimumMM else { continue }
                        total += Double(signedMM) / 1000.0 * Double(areas[i])
                    }
                }
                return max(total, 0.0) * 1000  // m³ → L
            }.value
            self?.estimatedVolumeLiters = liters
            self?.isComputingVolume = false
        }
    }

    // MARK: - ICP Alignment

    /// After giving the rescan session ~4 s to accumulate geometry, attempts an
    /// ICP alignment pass restricted to stable reference faces (floor, ceiling,
    /// doors). This corrects session-to-session coordinate-frame drift.
    private func scheduleAlignment(originalMesh: MeshBuffer) {
        let nonce = alignmentNonce
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            // Exit if the session was reset while we were waiting.
            guard self.alignmentNonce == nonce else { return }

            let rescanMesh = self.sessionManager.currentMeshBuffer()
            guard !rescanMesh.vertices.isEmpty else { return }

            let result: AlignmentResult? = await Task.detached(priority: .utility) {
                let sourceRef = rescanMesh.filteredByFace { $0.isStableReference }
                let targetRef = originalMesh.filteredByFace { $0.isStableReference }
                guard !sourceRef.vertices.isEmpty, !targetRef.vertices.isEmpty else { return nil }
                return ICPAligner.align(source: sourceRef, target: targetRef)
            }.value

            guard self.alignmentNonce == nonce else { return }
            guard let result, result.converged else { return }
            self.alignmentTransform = result.transform
        }
    }

    // MARK: - Finish

    var canFinish: Bool {
        sessionManager.meshAnchorCount > 0 && !isSaving
    }

    func finishAndSave(label: String) async {
        guard let folderManager, let originalScan,
              let project = try? di.projectRepository.fetchProject(id: projectID) else {
            errorMessage = "Project not found."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let rescanMesh = sessionManager.currentMeshBuffer()
        guard !rescanMesh.vertices.isEmpty else {
            errorMessage = ScanArtError.meshEmpty.localizedDescription
            return
        }

        do {
            let meshesFolder = try folderManager.meshesFolder(for: projectID)
            let originalMeshURL = meshesFolder.appendingPathComponent(originalScan.meshFileName)
            let originalMesh = try await Task.detached(priority: .userInitiated) {
                try MeshFileStorage.loadMesh(from: originalMeshURL)
            }.value

            // Refinement ICP restricted to stable-reference faces only — see
            // ICPAligner's doc comment for why running it on the wall itself
            // would bias thickness toward zero.
            let refinement: AlignmentResult? = await Task.detached(priority: .userInitiated) {
                let sourceRef = rescanMesh.filteredByFace { $0.isStableReference }
                let targetRef = originalMesh.filteredByFace { $0.isStableReference }
                guard !sourceRef.vertices.isEmpty, !targetRef.vertices.isEmpty else { return nil }
                return ICPAligner.align(source: sourceRef, target: targetRef)
            }.value

            let finalTransform = refinement?.transform ?? .identity
            let alignedMesh = refinement != nil ? rescanMesh.transformed(by: finalTransform) : rescanMesh

            let scanID = UUID()
            let meshURL = meshesFolder.appendingPathComponent("\(scanID.uuidString).scanmesh")
            try await Task.detached(priority: .userInitiated) {
                try MeshFileStorage.save(alignedMesh, to: meshURL)
            }.value

            var worldMapFileName: String?
            if let capturedWorldMap = try? await sessionManager.captureWorldMap() {
                let worldMapURL = meshesFolder.appendingPathComponent("\(scanID.uuidString).worldmap")
                try await Task.detached(priority: .userInitiated) {
                    try WorldMapArchiver.save(capturedWorldMap, to: worldMapURL)
                }.value
                worldMapFileName = worldMapURL.lastPathComponent
            }

            let bounds = alignedMesh.boundingBox()
            let area = SurfaceAreaCalculator.totalAreaSquareMeters(alignedMesh)
            let quality = ScanQuality.evaluate(
                coveragePercent: sessionManager.estimatedCoveragePercent,
                trackingWasStableRatio: sessionManager.trackingStabilityRatio
            )

            let scan = ScanRecord(
                id: scanID,
                scanType: .rescan,
                sequenceNumber: project.nextRescanSequenceNumber,
                label: label,
                meshFileName: meshURL.lastPathComponent,
                worldMapFileName: worldMapFileName,
                vertexCount: alignedMesh.vertexCount,
                faceCount: alignedMesh.faceCount,
                surfaceAreaSquareMeters: area,
                boundingBoxMin: (Double(bounds.min.x), Double(bounds.min.y), Double(bounds.min.z)),
                boundingBoxMax: (Double(bounds.max.x), Double(bounds.max.y), Double(bounds.max.z)),
                fileSizeBytes: fileSize(at: meshURL),
                isCompressed: true,
                alignmentTransform: refinement != nil ? finalTransform.flattened : nil,
                alignmentRMSEMM: refinement.map { Double($0.rmse) * 1000 },
                relocalizationSucceeded: sessionManager.relocalizationState == .relocalized,
                coveragePercent: sessionManager.estimatedCoveragePercent,
                scanQuality: quality
            )

            try di.scanRepository.addScan(scan, to: project)
            sessionManager.stop()
            savedScanID = scanID
            didSave = true
        } catch {
            errorMessage = "Couldn't save rescan: \(error.localizedDescription)"
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}
