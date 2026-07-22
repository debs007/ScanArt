import Foundation
import SwiftUI
import Combine
import ScanArtAR
import ScanArtAlgorithms
import ScanArtCore
import ScanArtPersistence

@MainActor
final class ScanViewModel: ObservableObject {
    let projectID: UUID
    let sessionManager = ARScanSessionManager()

    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false

    private let di: DIContainer
    private let folderManager: ProjectFolderManager?
    private var sessionManagerSubscription: AnyCancellable?

    init(projectID: UUID, di: DIContainer) {
        self.projectID = projectID
        self.di = di
        self.folderManager = try? ProjectFolderManager()
        // `sessionManager` publishes its own tracking/coverage/anchor-count
        // updates continuously during a scan; without forwarding those here,
        // this view model's `objectWillChange` would only fire for its own
        // properties (isSaving/errorMessage/didSave), and the live overlay
        // (coverage ring, tracking banner) would appear frozen.
        self.sessionManagerSubscription = sessionManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        sessionManager.startOriginalScan()
    }

    func stop() {
        sessionManager.pause()
    }

    var canFinish: Bool {
        sessionManager.meshAnchorCount > 0 && !isSaving
    }

    func finishAndSave(label: String) async {
        guard let folderManager else {
            errorMessage = "Couldn't access local storage."
            return
        }
        guard let project = try? di.projectRepository.fetchProject(id: projectID) else {
            errorMessage = "Project not found."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let mesh = sessionManager.currentMeshBuffer()
        guard !mesh.vertices.isEmpty else {
            errorMessage = ScanArtError.meshEmpty.localizedDescription
            return
        }

        do {
            let meshesFolder = try folderManager.meshesFolder(for: projectID)
            let scanID = UUID()
            let meshURL = meshesFolder.appendingPathComponent("\(scanID.uuidString).scanmesh")
            let capturedWorldMap = try? await sessionManager.captureWorldMap()

            // Compression + disk I/O for a room-scale mesh can take real time —
            // this app is @MainActor throughout for SwiftData safety, so the
            // heavy part is explicitly hopped off-actor rather than blocking
            // the UI for the couple of seconds a large scan can take to write.
            try await Task.detached(priority: .userInitiated) {
                try MeshFileStorage.save(mesh, to: meshURL)
            }.value

            var worldMapFileName: String?
            if let capturedWorldMap {
                let worldMapURL = meshesFolder.appendingPathComponent("\(scanID.uuidString).worldmap")
                try await Task.detached(priority: .userInitiated) {
                    try WorldMapArchiver.save(capturedWorldMap, to: worldMapURL)
                }.value
                worldMapFileName = worldMapURL.lastPathComponent
            }

            let bounds = mesh.boundingBox()
            let area = SurfaceAreaCalculator.totalAreaSquareMeters(mesh)
            let quality = ScanQuality.evaluate(
                coveragePercent: sessionManager.estimatedCoveragePercent,
                trackingWasStableRatio: sessionManager.trackingStabilityRatio
            )

            let scan = ScanRecord(
                id: scanID,
                scanType: .original,
                sequenceNumber: 0,
                label: label,
                meshFileName: meshURL.lastPathComponent,
                worldMapFileName: worldMapFileName,
                vertexCount: mesh.vertexCount,
                faceCount: mesh.faceCount,
                surfaceAreaSquareMeters: area,
                boundingBoxMin: (Double(bounds.min.x), Double(bounds.min.y), Double(bounds.min.z)),
                boundingBoxMax: (Double(bounds.max.x), Double(bounds.max.y), Double(bounds.max.z)),
                fileSizeBytes: fileSize(at: meshURL),
                isCompressed: true,
                coveragePercent: sessionManager.estimatedCoveragePercent,
                scanQuality: quality
            )

            try di.scanRepository.addScan(scan, to: project)
            sessionManager.stop()
            didSave = true
        } catch {
            errorMessage = "Couldn't save scan: \(error.localizedDescription)"
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}
