import SwiftUI
import PhotosUI
import ScanArtCore
import ScanArtUI

struct EditProjectView: View {
    let project: Project
    let onSaved: () -> Void

    @Environment(\.diContainer) private var di
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var customerName: String
    @State private var siteName: String
    @State private var buildingName: String
    @State private var roomName: String
    @State private var floorNumber: String
    @State private var engineerName: String
    @State private var notes: String
    @State private var unit: MeasurementUnit
    @State private var projectType: ProjectType
    @State private var desiredThickness: Double
    @State private var tolerance: Double

    @State private var thumbnailItem: PhotosPickerItem?
    @State private var thumbnailImage: UIImage?
    @State private var shouldRemoveThumbnail = false

    @State private var showClearConfirmation = false
    @State private var errorMessage: String?

    init(project: Project, onSaved: @escaping () -> Void) {
        self.project = project
        self.onSaved = onSaved
        let u = project.unit
        _name = State(initialValue: project.name)
        _customerName = State(initialValue: project.customerName)
        _siteName = State(initialValue: project.siteName)
        _buildingName = State(initialValue: project.buildingName)
        _roomName = State(initialValue: project.roomName)
        _floorNumber = State(initialValue: project.floorNumber)
        _engineerName = State(initialValue: project.engineerName)
        _notes = State(initialValue: project.notes)
        _unit = State(initialValue: u)
        _projectType = State(initialValue: project.projectType)
        _desiredThickness = State(initialValue: u.fromMillimeters(project.desiredThicknessMM))
        _tolerance = State(initialValue: u.fromMillimeters(project.toleranceMM))
    }

    var body: some View {
        NavigationStack {
            Form {
                thumbnailSection

                Section {
                    iconRow("folder.fill", color: ScanArtTheme.accent) {
                        TextField("Project name *", text: $name).autocorrectionDisabled()
                    }
                    iconRow("person.fill", color: .blue) {
                        TextField("Customer name", text: $customerName)
                    }
                    iconRow("person.badge.key.fill", color: .purple) {
                        TextField("Engineer name", text: $engineerName)
                    }
                } header: { Label("Project", systemImage: "briefcase") }

                Section {
                    iconRow("mappin.circle.fill", color: .red) {
                        TextField("Site", text: $siteName)
                    }
                    iconRow("building.2.fill", color: .orange) {
                        TextField("Building", text: $buildingName)
                    }
                    iconRow("door.left.hand.open", color: .teal) {
                        TextField("Room", text: $roomName)
                    }
                    iconRow("square.stack.fill", color: .indigo) {
                        TextField("Floor number", text: $floorNumber).keyboardType(.numberPad)
                    }
                } header: { Label("Location", systemImage: "location") }

                Section {
                    Picker(selection: $projectType) {
                        ForEach(ProjectType.allCases) { Text($0.displayName).tag($0) }
                    } label: { Label("Work Type", systemImage: "paintbrush.pointed.fill") }
                    .pickerStyle(.navigationLink)

                    Picker(selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { Text($0.displayName).tag($0) }
                    } label: { Label("Unit", systemImage: "ruler") }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Target \(projectType.thicknessLabel.lowercased())", systemImage: "arrow.up.and.down")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(thicknessDisplay)
                                .foregroundStyle(ScanArtTheme.accent)
                                .monospacedDigit().fontWeight(.semibold)
                        }
                        Slider(value: $desiredThickness, in: thicknessRange, step: thicknessStep)
                            .tint(ScanArtTheme.accent)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Tolerance (±)", systemImage: "plusminus").foregroundStyle(.primary)
                            Spacer()
                            Text(toleranceDisplay)
                                .foregroundStyle(.orange)
                                .monospacedDigit().fontWeight(.semibold)
                        }
                        Slider(value: $tolerance, in: toleranceRange, step: toleranceStep).tint(.orange)
                    }
                    .padding(.vertical, 4)
                } header: { Label("Target \(projectType.thicknessLabel)", systemImage: "chart.bar.xaxis") }

                Section {
                    TextEditor(text: $notes).frame(minHeight: 80)
                } header: { Label("Notes", systemImage: "note.text") }

                if !project.scans.isEmpty {
                    Section {
                        Label(
                            "Saving will permanently delete \(project.scans.count) scan(s) and all thickness results.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(ScanArtTheme.body(13))
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(ScanArtTheme.statusDanger)
                    }
                }
            }
            .onChange(of: unit) { old, new in
                let desMM = old.toMillimeters(desiredThickness)
                let tolMM = old.toMillimeters(tolerance)
                desiredThickness = min(max(thicknessRange.lowerBound, new.fromMillimeters(desMM)), thicknessRange.upperBound)
                tolerance = min(max(toleranceRange.lowerBound, new.fromMillimeters(tolMM)), toleranceRange.upperBound)
            }
            .onChange(of: thumbnailItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        thumbnailImage = image
                        shouldRemoveThumbnail = false
                    }
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if project.scans.isEmpty {
                            saveProject()
                        } else {
                            showClearConfirmation = true
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(
                "Delete all scan data?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Scans & Save", role: .destructive) { saveProject() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saving will permanently delete all original scans, rescans, and thickness analysis results for this project.")
            }
        }
    }

    // MARK: - Thumbnail section

    private var thumbnailSection: some View {
        Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $thumbnailItem, matching: .images) {
                    thumbnailPreview
                }
                Spacer()
            }
            .padding(.vertical, 4)
            if thumbnailImage != nil || (project.thumbnailFileName != nil && !shouldRemoveThumbnail) {
                Button("Remove Photo", role: .destructive) {
                    thumbnailImage = nil
                    thumbnailItem = nil
                    shouldRemoveThumbnail = true
                }
            }
        } header: { Label("Project Photo", systemImage: "photo") }
    }

    @ViewBuilder
    private var thumbnailPreview: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM))
                .overlay(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM).stroke(ScanArtTheme.accent, lineWidth: 2))
        } else if !shouldRemoveThumbnail, let url = existingThumbnailURL {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else { placeholderIcon }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM).stroke(ScanArtTheme.accent, lineWidth: 2))
        } else {
            placeholderIcon
                .frame(width: 88, height: 88)
        }
    }

    private var placeholderIcon: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(ScanArtTheme.accent)
            Text("Add Photo")
                .font(ScanArtTheme.body(12))
                .foregroundStyle(ScanArtTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScanArtTheme.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM))
    }

    private var existingThumbnailURL: URL? {
        guard let filename = project.thumbnailFileName else { return nil }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false) else { return nil }
        return appSupport.appendingPathComponent("ScanArt/Projects/\(project.id.uuidString)/Images/\(filename)")
    }

    // MARK: - Save

    private func saveProject() {
        guard let di else { return }
        if !project.scans.isEmpty { clearScans() }

        project.name = name.trimmingCharacters(in: .whitespaces)
        project.customerName = customerName
        project.siteName = siteName
        project.buildingName = buildingName
        project.roomName = roomName
        project.floorNumber = floorNumber
        project.engineerName = engineerName
        project.notes = notes
        project.unit = unit
        project.projectType = projectType
        project.desiredThicknessMM = unit.toMillimeters(desiredThickness)
        project.toleranceMM = unit.toMillimeters(tolerance)
        project.dateModified = Date()

        if let image = thumbnailImage {
            saveThumbnail(image)
        } else if shouldRemoveThumbnail {
            if let url = existingThumbnailURL { try? FileManager.default.removeItem(at: url) }
            project.thumbnailFileName = nil
        }

        do {
            try di.projectRepository.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func clearScans() {
        guard let di else { return }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false) else { return }

        for scan in project.scans {
            let meshURL = appSupport.appendingPathComponent("ScanArt/Projects/\(project.id.uuidString)/Meshes/\(scan.meshFileName)")
            try? FileManager.default.removeItem(at: meshURL)
            for result in scan.thicknessResults {
                let samplesURL = appSupport.appendingPathComponent("ScanArt/Projects/\(project.id.uuidString)/Thickness/\(result.samplesFileName)")
                try? FileManager.default.removeItem(at: samplesURL)
            }
            try? di.scanRepository.deleteScan(scan)
        }
    }

    private func saveThumbnail(_ image: UIImage) {
        let thumb = image.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? image
        guard let data = thumb.jpegData(compressionQuality: 0.8) else { return }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false) else { return }
        let folder = appSupport.appendingPathComponent("ScanArt/Projects/\(project.id.uuidString)/Images")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent("thumbnail.jpg"), options: .atomic)
        project.thumbnailFileName = "thumbnail.jpg"
    }

    // MARK: - Slider config (mirrors CreateProjectView)

    private var thicknessRange: ClosedRange<Double> {
        switch unit {
        case .millimeters: return 0...500
        case .centimeters: return 0...50
        case .inches:      return 0...20
        }
    }
    private var thicknessStep: Double {
        switch unit {
        case .millimeters: return 5.0    // 0.5 cm resolution
        case .centimeters: return 0.5
        case .inches:      return 0.25
        }
    }
    private var toleranceRange: ClosedRange<Double> {
        switch unit {
        case .millimeters: return 0...50
        case .centimeters: return 0...5
        case .inches:      return 0...2
        }
    }
    private var toleranceStep: Double {
        switch unit {
        case .millimeters: return 0.5
        case .centimeters: return 0.05
        case .inches:      return 0.02
        }
    }
    private var thicknessDisplay: String {
        switch unit {
        case .millimeters: return String(format: "%.0f mm", desiredThickness)
        case .centimeters: return String(format: "%.1f cm", desiredThickness)
        case .inches:      return String(format: "%.2f in", desiredThickness)
        }
    }
    private var toleranceDisplay: String {
        switch unit {
        case .millimeters: return String(format: "%.1f mm", tolerance)
        case .centimeters: return String(format: "%.2f cm", tolerance)
        case .inches:      return String(format: "%.2f in", tolerance)
        }
    }

    @ViewBuilder
    private func iconRow<Content: View>(_ systemImage: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(color).frame(width: 28, alignment: .center)
            content()
        }
    }
}
