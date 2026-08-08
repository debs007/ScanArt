import Foundation
import ScanArtCore
import ScanArtAlgorithms

/// App-level extension that keeps ScanArtCore free of ScanArtAlgorithms as a
/// dependency while still exposing a convenient colorMapper() API on Project.
extension Project {

    /// Returns a ThicknessColorMapper using the project's fully custom stops
    /// (color + threshold per band) if saved, otherwise the standard palette.
    func colorMapper() -> ThicknessColorMapper {
        guard let json = customColorStopsJSON,
              let data = json.data(using: .utf8),
              let stops = try? JSONDecoder().decode([ColorStop].self, from: data),
              !stops.isEmpty else {
            return ThicknessColorMapper.standard(
                desiredThicknessMM: desiredThicknessMM,
                toleranceMM: toleranceMM
            )
        }
        return ThicknessColorMapper(stops: stops)
    }

    /// Persists a fully custom stop array (both color and threshold per band).
    func saveCustomStops(_ stops: [ColorStop]) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        customColorStopsJSON = String(data: data, encoding: .utf8)
        dateModified = Date()
    }

    /// Removes the custom palette so the project reverts to the standard palette.
    func resetCustomColors() {
        customColorStopsJSON = nil
        dateModified = Date()
    }

    var hasCustomColors: Bool { customColorStopsJSON != nil }
}
