import SwiftUI
import ScanArtCore
import ScanArtPersistence
import ScanArtUI

struct SettingsView: View {
    @AppStorage("scanart.defaultUnit") private var defaultUnitRawValue: String = MeasurementUnit.centimeters.rawValue
    @Environment(LocalizationManager.self) private var l10n
    @State private var availableStorageMB: Double?

    private var defaultUnit: Binding<MeasurementUnit> {
        Binding(
            get: { MeasurementUnit(rawValue: defaultUnitRawValue) ?? .centimeters },
            set: { defaultUnitRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(l10n("settings.defaults")) {
                Picker(l10n("settings.defaultUnit"), selection: defaultUnit) {
                    ForEach(MeasurementUnit.allCases) { Text($0.displayName).tag($0) }
                }
                Text(l10n("settings.defaultUnitNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(l10n("settings.language")) {
                Picker(l10n("settings.language"), selection: Binding(
                    get: { l10n.language },
                    set: { l10n.setLanguage($0) }
                )) {
                    Text(l10n("settings.language.en")).tag("en")
                    Text(l10n("settings.language.es")).tag("es")
                }
                .pickerStyle(.segmented)
                Text(l10n("settings.language.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(l10n("settings.storage")) {
                LabeledContent(l10n("settings.availableSpace")) {
                    if let availableStorageMB {
                        Text(availableStorageMB > 1024
                             ? String(format: "%.1f GB", availableStorageMB / 1024)
                             : String(format: "%.0f MB", availableStorageMB))
                    } else {
                        Text("—")
                    }
                }
                Text(l10n("settings.storageNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(l10n("settings.version"), value: appVersionString)
            }
        }
        .navigationTitle(l10n("settings.title"))
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
