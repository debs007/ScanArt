import Foundation

/// Display unit preference. All measurements are stored internally in
/// millimeters (see model docs) — this only controls formatting.
public enum MeasurementUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case millimeters = "mm"
    case centimeters = "cm"
    case inches = "in"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .millimeters: return "Millimeters (mm)"
        case .centimeters: return "Centimeters (cm)"
        case .inches: return "Inches (in)"
        }
    }

    public func fromMillimeters(_ mm: Double) -> Double {
        switch self {
        case .millimeters: return mm
        case .centimeters: return mm / 10
        case .inches: return mm / 25.4
        }
    }

    public func toMillimeters(_ value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .centimeters: return value * 10
        case .inches: return value * 25.4
        }
    }

    /// Formats a millimeter value in this unit, e.g. "4.0 cm".
    public func format(mm: Double, decimals: Int = 1) -> String {
        let converted = fromMillimeters(mm)
        return String(format: "%.\(decimals)f %@", converted, rawValue)
    }
}

public enum ScanType: String, Codable, Sendable {
    case original
    case rescan
}

public enum ScanQuality: String, Codable, Sendable, CaseIterable {
    case poor, fair, good, excellent

    /// Derived from live coverage % + tracking stability while scanning.
    public static func evaluate(coveragePercent: Double, trackingWasStableRatio: Double) -> ScanQuality {
        let score = coveragePercent * 0.7 + trackingWasStableRatio * 100 * 0.3
        switch score {
        case ..<40: return .poor
        case 40..<65: return .fair
        case 65..<85: return .good
        default: return .excellent
        }
    }
}

/// Whether the project measures material being added (plaster, render coat, etc.)
/// or material being removed (chasing, excavation, grinding).
///
/// This controls:
///   - Color legend labels in the live AR view
///   - Volume calculation direction (positive vs negative thickness)
///   - Statistics and report labels
public enum ProjectType: String, Codable, CaseIterable, Sendable, Identifiable {
    case plaster    = "plaster"
    case excavation = "excavation"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plaster:    return "Plaster / Coating"
        case .excavation: return "Excavation / Removal"
        }
    }

    /// Short label for "how thick is the material" in this mode.
    public var thicknessLabel: String {
        switch self {
        case .plaster:    return "Thickness"
        case .excavation: return "Depth"
        }
    }

    /// Label for the volume section in statistics and PDF reports.
    public var volumeLabel: String {
        switch self {
        case .plaster:    return "Plaster Volume"
        case .excavation: return "Excavation Volume"
        }
    }

    /// Color-legend labels ordered blue → yellow → green → orange → red.
    public var legendLabels: [String] {
        switch self {
        case .plaster:    return ["Bare", "Thin", "Target", "Over", "Thick"]
        case .excavation: return ["Surface", "Shallow", "Target", "Deep", "Too Deep"]
        }
    }

    /// Human-readable description shown on the Analysis screen.
    public var measurementDescription: String {
        switch self {
        case .plaster:    return "plaster thickness"
        case .excavation: return "excavation depth"
        }
    }
}
