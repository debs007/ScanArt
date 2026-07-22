import SwiftUI
import ScanArtCore
import ScanArtPersistence
import ScanArtUI

struct SettingsView: View {
    @AppStorage("scanart.defaultUnit") private var defaultUnitRawValue: String = MeasurementUnit.centimeters.rawValue
    @State private var availableStorageMB: Double?

    private var defaultUnit: Binding<MeasurementUnit> {
        Binding(
            get: { MeasurementUnit(rawValue: defaultUnitRawValue) ?? .centimeters },
            set: { defaultUnitRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default Unit", selection: defaultUnit) {
                    ForEach(MeasurementUnit.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Used to pre-fill new projects. Each project can still use its own unit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Available Space") {
                    if let availableStorageMB {
                        Text(availableStorageMB > 1024 ? String(format: "%.1f GB", availableStorageMB / 1024) : String(format: "%.0f MB", availableStorageMB))
                    } else {
                        Text("—")
                    }
                }
                Text("Scan Art stores all projects, scans, and reports locally on this device — nothing is uploaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: appVersionString)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadStorage() }
    }

    private func loadStorage() {
        if let manager = try? ProjectFolderManager() {
            availableStorageMB = manager.availableCapacityMB()
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
