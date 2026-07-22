import Foundation

/// Centralized error type covering the spec's "Error Handling" section
/// (low light / tracking lost / poor scan / incomplete scan / low battery /
/// storage full / LiDAR unavailable) plus persistence and export failures.
/// Each case carries a `recoverySuggestion` suitable for direct display.
public enum ScanArtError: LocalizedError, Sendable {
    case lidarUnavailable
    case trackingLost
    case relocalizationFailed
    case insufficientCoverage(percent: Double)
    case lowLight
    case lowBattery(percent: Double)
    case storageFull(availableMB: Double, requiredEstimateMB: Double)
    case worldMapCaptureFailed
    case meshEmpty
    case exportFailed(format: String, underlying: String)
    case fileSystem(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .lidarUnavailable:
            return "This device is not supported."
        case .trackingLost:
            return "AR tracking was lost."
        case .relocalizationFailed:
            return "Couldn't align this rescan to the original scan's position."
        case .insufficientCoverage(let percent):
            return "Only \(Int(percent))% of the wall was scanned."
        case .lowLight:
            return "Lighting is too low for accurate scanning."
        case .lowBattery(let percent):
            return "Battery is at \(Int(percent))%."
        case .storageFull(let available, let required):
            return "Not enough storage: \(Int(available)) MB free, ~\(Int(required)) MB needed."
        case .worldMapCaptureFailed:
            return "Couldn't save this scan's spatial map."
        case .meshEmpty:
            return "No mesh data was captured."
        case .exportFailed(let format, _):
            return "Couldn't export to \(format)."
        case .fileSystem(let detail):
            return "A storage error occurred: \(detail)"
        case .unknown(let detail):
            return detail
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .lidarUnavailable:
            return "Scan Art requires a LiDAR Scanner, available on iPhone Pro and iPad Pro models. This device doesn't have one."
        case .trackingLost:
            return "Move to a well-lit area, avoid blank or reflective surfaces, and hold the device steady."
        case .relocalizationFailed:
            return "Slowly pan the device around the room, including some of the floor, ceiling, or a doorway, so ARKit can recognize the space. You can also fine-tune alignment manually."
        case .insufficientCoverage:
            return "Continue scanning until coverage is higher, especially near the edges of the wall."
        case .lowLight:
            return "Turn on more lighting or move closer to a light source before continuing."
        case .lowBattery:
            return "Scanning uses the camera and LiDAR continuously — consider charging before a long scan."
        case .storageFull:
            return "Free up space or export/delete older projects, then try again."
        case .worldMapCaptureFailed:
            return "Try again, keeping the device moving slowly and steadily during capture."
        case .meshEmpty:
            return "Point the device at the wall and move slowly until the mesh starts to appear."
        case .exportFailed:
            return "Try exporting again, or choose a different format."
        case .fileSystem, .unknown:
            return "If this keeps happening, restart the app."
        }
    }
}
