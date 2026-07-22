import SwiftUI
import ScanArtCore
import ScanArtUI

struct CreateProjectView: View {
    let onCreated: (UUID) -> Void

    @Environment(\.diContainer) private var di
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var customerName = ""
    @State private var siteName = ""
    @State private var buildingName = ""
    @State private var roomName = ""
    @State private var floorNumber = ""
    @State private var engineerName = ""
    @State private var notes = ""
    @State private var unit: MeasurementUnit = .centimeters
    @State private var projectType: ProjectType = .plaster
    // Slider values stored in the currently selected unit
    @State private var desiredThickness: Double = 4.0   // default 4 cm = 40 mm
    @State private var tolerance: Double = 0.2          // default 0.2 cm = 2 mm
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    iconRow("folder.fill", color: ScanArtTheme.accent) {
                        TextField("Project name *", text: $name)
                            .autocorrectionDisabled()
                    }
                    iconRow("person.fill", color: .blue) {
                        TextField("Customer name", text: $customerName)
                    }
                    iconRow("person.badge.key.fill", color: .purple) {
                        TextField("Engineer name", text: $engineerName)
                    }
                } header: {
                    Label("Project", systemImage: "briefcase")
                }

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
                        TextField("Floor number", text: $floorNumber)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Label("Location", systemImage: "location")
                }

                Section {
                    Picker(selection: $projectType) {
                        ForEach(ProjectType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    } label: {
                        Label("Work Type", systemImage: "paintbrush.pointed.fill")
                    }
                    .pickerStyle(.navigationLink)

                    Picker(selection: $unit) {
                        ForEach(MeasurementUnit.allCases) { Text($0.displayName).tag($0) }
                    } label: {
                        Label("Unit", systemImage: "ruler")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                "Target \(projectType.thicknessLabel.lowercased())",
                                systemImage: "arrow.up.and.down"
                            )
                            .foregroundStyle(.primary)
                            Spacer()
                            Text(thicknessDisplay)
                                .foregroundStyle(ScanArtTheme.accent)
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(
                            value: $desiredThickness,
                            in: thicknessRange,
                            step: thicknessStep
                        )
                        .tint(ScanArtTheme.accent)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Tolerance (±)", systemImage: "plusminus")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(toleranceDisplay)
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(
                            value: $tolerance,
                            in: toleranceRange,
                            step: toleranceStep
                        )
                        .tint(.orange)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Target \(projectType.thicknessLabel)", systemImage: "chart.bar.xaxis")
                }

                Section {
                    TextEditor(text: $notes).frame(minHeight: 80)
                } header: {
                    Label("Notes", systemImage: "note.text")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(ScanArtTheme.statusDanger)
                    }
                }
            }
            .onChange(of: unit) { old, new in
                // Convert the slider values to the new unit so the physical
                // quantity stays the same after switching units.
                let desMM = old.toMillimeters(desiredThickness)
                let tolMM = old.toMillimeters(tolerance)
                let newDes = new.fromMillimeters(desMM)
                let newTol = new.fromMillimeters(tolMM)
                desiredThickness = min(max(thicknessRange.lowerBound, newDes), thicknessRange.upperBound)
                tolerance = min(max(toleranceRange.lowerBound, newTol), toleranceRange.upperBound)
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Slider configuration

    private var thicknessRange: ClosedRange<Double> {
        switch unit {
        case .millimeters: return 0...100
        case .centimeters: return 0...10
        case .inches:      return 0...4
        }
    }

    private var thicknessStep: Double {
        switch unit {
        case .millimeters: return 1.0
        case .centimeters: return 0.1
        case .inches:      return 0.05
        }
    }

    private var toleranceRange: ClosedRange<Double> {
        switch unit {
        case .millimeters: return 0...10
        case .centimeters: return 0...1
        case .inches:      return 0...0.4
        }
    }

    private var toleranceStep: Double {
        switch unit {
        case .millimeters: return 0.5
        case .centimeters: return 0.05
        case .inches:      return 0.02
        }
    }

    // MARK: - Display formatting

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

    // MARK: - Helpers

    @ViewBuilder
    private func iconRow<Content: View>(_ systemImage: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 28, alignment: .center)
            content()
        }
    }

    private func create() {
        guard let di else { return }

        let project = Project(
            name: name.trimmingCharacters(in: .whitespaces),
            customerName: customerName,
            engineerName: engineerName,
            siteName: siteName,
            buildingName: buildingName,
            roomName: roomName,
            floorNumber: floorNumber,
            notes: notes,
            desiredThicknessMM: unit.toMillimeters(desiredThickness),
            toleranceMM: unit.toMillimeters(tolerance),
            unit: unit,
            projectType: projectType
        )

        do {
            try di.projectRepository.createProject(project)
            onCreated(project.id)
        } catch {
            errorMessage = "Couldn't create project: \(error.localizedDescription)"
        }
    }
}
