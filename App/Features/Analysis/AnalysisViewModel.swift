import Foundation
import SwiftUI
import ScanArtAlgorithms
import ScanArtRendering
import ScanArtExport
import ScanArtCore
import ScanArtPersistence

@MainActor
final class AnalysisViewModel: ObservableObject {
    let projectID: UUID
    let scanID: UUID

    @Published private(set) var project: Project?
    @Published private(set) var scan: ScanRecord?
    @Published private(set) var statistics: ThicknessStatistics = .empty
    @Published private(set) var volumeCubicMeters: Double = 0
    @Published private(set) var isGenerating = false
    @Published private(set) var hasResult = false
    @Published var errorMessage: String?
    @Published var isExporting = false
    @Published var lastExportURL: URL?
    @Published var isGeneratingReport = false
    @Published var lastReportURL: URL?

    let meshViewController = MeshViewController(isOpaqueBackground: true)!

    private let di: DIContainer
    private let folderManager: ProjectFolderManager?
    private var originalMesh: MeshBuffer?
    private var currentSamples: [ThicknessSample]?
    private var colorMapper: ThicknessColorMapper = .standard(desiredThicknessMM: 40, toleranceMM: 2)

    init(projectID: UUID, scanID: UUID, di: DIContainer) {
        self.projectID = projectID
        self.scanID = scanID
        self.di = di
        self.folderManager = try? ProjectFolderManager()
    }

    func load() async {
        guard folderManager != nil else {
            errorMessage = "Couldn't access local storage."
            return
        }
        do {
            guard let loadedProject = try di.projectRepository.fetchProject(id: projectID) else {
                errorMessage = "Project not found."
                return
            }
            project = loadedProject
            colorMapper = .standard(desiredThicknessMM: loadedProject.desiredThicknessMM, toleranceMM: loadedProject.toleranceMM)
            guard let loadedScan = loadedProject.scans.first(where: { $0.id == scanID }) else {
                errorMessage = "Scan not found."
                return
            }
            scan = loadedScan

            if let existing = loadedScan.thicknessResults.first {
                try await loadExistingResult(existing, scan: loadedScan, project: loadedProject)
            } else {
                try await loadPlainMesh(scan: loadedScan)
            }
        } catch {
            errorMessage = "Couldn't load scan data: \(error.localizedDescription)"
        }
    }

    private func loadPlainMesh(scan: ScanRecord) async throws {
        guard let folderManager else { return }
        let meshesFolder = try folderManager.meshesFolder(for: projectID)
        let url = meshesFolder.appendingPathComponent(scan.meshFileName)
        let mesh = try await Task.detached(priority: .userInitiated) {
            try MeshFileStorage.loadMesh(from: url)
        }.value
        meshViewController.renderer.displayMode = .plain
        meshViewController.renderer.setMesh(mesh)
        let bounds = mesh.boundingBox()
        meshViewController.renderer.camera.frame(boundingMin: bounds.min, boundingMax: bounds.max)
    }

    private func loadExistingResult(_ result: ThicknessResult, scan: ScanRecord, project: Project) async throws {
        guard let folderManager else { return }
        let meshesFolder = try folderManager.meshesFolder(for: projectID)
        let thicknessFolder = try folderManager.thicknessFolder(for: projectID)

        let meshURL = meshesFolder.appendingPathComponent(scan.meshFileName)
        let samplesURL = thicknessFolder.appendingPathComponent(result.samplesFileName)

        let (mesh, samples) = try await Task.detached(priority: .userInitiated) {
            let mesh = try MeshFileStorage.loadMesh(from: meshURL)
            let samples = try MeshFileStorage.loadSamples(from: samplesURL)
            return (mesh, samples)
        }.value

        currentSamples = samples
        statistics = ThicknessStatistics.compute(samples: samples, desiredThicknessMM: project.desiredThicknessMM, toleranceMM: project.toleranceMM)
        volumeCubicMeters = result.volumeCubicMeters
        hasResult = true

        meshViewController.renderer.displayMode = .heatmap
        meshViewController.renderer.setHeatmapMesh(original: mesh, samples: samples, colorMapper: colorMapper)
        let bounds = mesh.boundingBox()
        meshViewController.renderer.camera.frame(boundingMin: bounds.min, boundingMax: bounds.max)
    }

    /// The spec's explicit "Generate thickness map" step: compares this scan
    /// against the project's original scan.
    func generateThicknessMap() async {
        guard let folderManager, let project, let scan, let original = project.originalScan else {
            errorMessage = "This project has no original scan to compare against."
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        do {
            let meshesFolder = try folderManager.meshesFolder(for: projectID)
            let originalURL = meshesFolder.appendingPathComponent(original.meshFileName)
            let rescanURL = meshesFolder.appendingPathComponent(scan.meshFileName)

            let (originalMesh, rescanMesh) = try await Task.detached(priority: .userInitiated) {
                let o = try MeshFileStorage.loadMesh(from: originalURL)
                let r = try MeshFileStorage.loadMesh(from: rescanURL)
                return (o, r)
            }.value
            self.originalMesh = originalMesh

            // Re-align the rescan mesh to the original before measuring. The saved
            // rescan mesh may already be aligned (ICP succeeded at save time) or not
            // (no stable reference faces were visible). Re-running ICP here is safe:
            // if already aligned it produces a near-identity transform that doesn't
            // double-apply; if not aligned it corrects the coordinate frame drift
            // that would otherwise cause all ray casts to miss → volume = 0.
            let alignedRescanMesh = await Task.detached(priority: .userInitiated) {
                let sourceRef = rescanMesh.filteredByFace { $0.isStableReference }
                let targetRef = originalMesh.filteredByFace { $0.isStableReference }
                guard !sourceRef.vertices.isEmpty, !targetRef.vertices.isEmpty else { return rescanMesh }
                let result = ICPAligner.align(source: sourceRef, target: targetRef)
                guard result.converged else { return rescanMesh }
                return rescanMesh.transformed(by: result.transform)
            }.value

            // Measurement restricted to wall faces when classification is available.
            let originalWall = originalMesh.faceClassifications.isEmpty ? originalMesh : originalMesh.filteredByFace { $0.isMeasurementTarget }
            let targetForMeasurement = originalWall.vertices.isEmpty ? originalMesh : originalWall

            let rawSamples = await ThicknessCalculator.compute(original: targetForMeasurement, rescan: alignedRescanMesh)

            // For excavation: flip signs so stats/rendering see positive depth values.
            // Volume uses the original signed samples so direction filtering works.
            let isExcavation = project.projectType == .excavation
            let displaySamples: [ThicknessSample]
            if isExcavation {
                displaySamples = rawSamples.map { s in
                    s.isValid
                        ? ThicknessSample(position: s.position, normal: s.normal, thicknessMM: abs(s.thicknessMM), isValid: true)
                        : s
                }
            } else {
                displaySamples = rawSamples
            }

            let stats = ThicknessStatistics.compute(
                samples: displaySamples,
                desiredThicknessMM: project.desiredThicknessMM,
                toleranceMM: project.toleranceMM
            )
            let vertexAreas = SurfaceAreaCalculator.vertexAreas(targetForMeasurement)

            // Only count samples at or above the "green" threshold.
            let minimumMM = max(0, project.desiredThicknessMM - project.toleranceMM)
            let volume = VolumeCalculator.computeCubicMeters(
                samples: rawSamples,
                vertexAreas: vertexAreas,
                minimumContributionMM: minimumMM,
                isExcavation: isExcavation
            )

            let thicknessFolder = try folderManager.thicknessFolder(for: projectID)
            let resultID = UUID()
            let samplesURL = thicknessFolder.appendingPathComponent("\(resultID.uuidString)_samples.bin")
            try await Task.detached(priority: .userInitiated) {
                try MeshFileStorage.saveSamples(displaySamples, to: samplesURL)
            }.value

            let result = ThicknessResult(
                id: resultID,
                comparedAgainstScanID: original.id,
                samplesFileName: samplesURL.lastPathComponent,
                method: "rayMeshIntersection",
                sampleCount: stats.sampleCount,
                validSampleCount: stats.validSampleCount,
                averageMM: stats.averageMM,
                minimumMM: stats.minimumMM,
                maximumMM: stats.maximumMM,
                medianMM: stats.medianMM,
                standardDeviationMM: stats.standardDeviationMM,
                withinTolerancePercent: stats.withinTolerancePercent,
                outOfTolerancePercent: stats.outOfTolerancePercent,
                volumeCubicMeters: volume
            )
            try di.thicknessResultRepository.addResult(result, to: scan)

            currentSamples = displaySamples
            statistics = stats
            volumeCubicMeters = volume
            hasResult = true

            meshViewController.renderer.displayMode = .heatmap
            meshViewController.renderer.setHeatmapMesh(original: targetForMeasurement, samples: displaySamples, colorMapper: colorMapper)
            let bounds = targetForMeasurement.boundingBox()
            meshViewController.renderer.camera.frame(boundingMin: bounds.min, boundingMax: bounds.max)
        } catch {
            errorMessage = "Couldn't generate thickness map: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func export(format: ExportFormat) async {
        guard let folderManager, let project, let scan else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let mesh: MeshBuffer
            if let originalMesh {
                mesh = originalMesh
            } else {
                let meshesFolder = try folderManager.meshesFolder(for: projectID)
                mesh = try MeshFileStorage.loadMesh(from: meshesFolder.appendingPathComponent(scan.meshFileName))
            }

            let payload = ExportPayload(
                mesh: mesh,
                samples: currentSamples,
                colorMapper: colorMapper,
                projectName: project.name,
                scanLabel: scan.displayName
            )

            let exportsFolder = try folderManager.exportsFolder(for: projectID)
            let fileName = "\(sanitizedFileName(project.name))_\(sanitizedFileName(scan.displayName)).\(format.fileExtension)"
            let url = exportsFolder.appendingPathComponent(fileName)

            try await Task.detached(priority: .userInitiated) {
                switch format {
                case .dxf: try DXFExporter.export(payload, to: url)
                case .obj: try OBJExporter.export(payload, to: url)
                case .ply: try PLYExporter.export(payload, to: url)
                case .stl: try STLExporter.export(payload, to: url)
                case .usdz: try USDZExporter.export(payload, to: url)
                case .csv: try CSVExporter.export(payload, to: url)
                case .json: try JSONExporter.export(payload, to: url)
                case .pdf: throw ExportError.missingData("Use generateReport() for PDF reports.")
                }
            }.value

            lastExportURL = url
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func generateReport() async {
        guard let folderManager, let project, let scan, hasResult else { return }
        isGeneratingReport = true
        defer { isGeneratingReport = false }

        do {
            let reportsFolder = try folderManager.reportsFolder(for: projectID)
            let reportID = UUID()
            let fileName = "\(sanitizedFileName(project.name))_Report_\(reportID.uuidString.prefix(8)).pdf"
            let url = reportsFolder.appendingPathComponent(fileName)

            let content = ReportContent(
                project: project,
                scan: scan,
                statistics: statistics,
                volumeCubicMeters: volumeCubicMeters,
                colorMapper: colorMapper
            )
            try PDFReportGenerator.generate(content, to: url)

            let record = ReportRecord(
                id: reportID,
                title: "\(project.name) — \(scan.displayName)",
                pdfFileName: fileName,
                includedScanIDs: [scan.id],
                engineerName: project.engineerName,
                customerName: project.customerName
            )
            try di.reportRepository.addReport(record, to: project)
            lastReportURL = url
        } catch {
            errorMessage = "Couldn't generate report: \(error.localizedDescription)"
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned)
        return result.isEmpty ? "ScanArt" : result
    }
}
