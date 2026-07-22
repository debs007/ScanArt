import Foundation

public enum VolumeUnit: String, Sendable, CaseIterable, Codable {
    case cubicMeters, liters, cubicFeet

    public func convert(fromCubicMeters value: Double) -> Double {
        switch self {
        case .cubicMeters: return value
        case .liters: return value * 1000
        case .cubicFeet: return value * 35.3147
        }
    }

    public var symbol: String {
        switch self {
        case .cubicMeters: return "m³"
        case .liters: return "L"
        case .cubicFeet: return "ft³"
        }
    }
}

public enum VolumeCalculator {

    /// Volume = sum over samples of (|thickness| * area of influence).
    ///
    /// - `minimumContributionMM`: Only samples whose magnitude is ≥ this
    ///   threshold contribute. Pass `desiredThicknessMM - toleranceMM` to
    ///   exclude "bare/thin" areas (below green on the heatmap) from the total.
    ///   Default 0 includes all valid samples regardless of magnitude.
    ///
    /// - `isExcavation`: When true, only samples with negative `thicknessMM`
    ///   (surface receded — material removed) contribute. When false (plaster),
    ///   only positive samples (surface advanced — material added) contribute.
    ///
    /// `vertexAreas` must be computed from the SAME original mesh that produced
    /// `samples` (same indexing) — see `SurfaceAreaCalculator.vertexAreas`.
    public static func computeCubicMeters(
        samples: [ThicknessSample],
        vertexAreas: [Float],
        minimumContributionMM: Double = 0,
        isExcavation: Bool = false
    ) -> Double {
        guard samples.count == vertexAreas.count else {
            assertionFailure("samples and vertexAreas must be parallel arrays from the same mesh")
            return 0
        }
        var total: Double = 0
        let threshold = Float(minimumContributionMM)
        for i in 0..<samples.count where samples[i].isValid {
            let mm = samples[i].thicknessMM
            if isExcavation {
                // Excavation: surface receded into the wall = negative thickness.
                // Only count samples that have been excavated at least to threshold.
                guard mm <= -threshold else { continue }
                total += Double(-mm) / 1000 * Double(vertexAreas[i])
            } else {
                // Plaster: surface advanced toward camera = positive thickness.
                // Only count samples at or above the green threshold.
                guard mm >= threshold else { continue }
                total += Double(mm) / 1000 * Double(vertexAreas[i])
            }
        }
        return max(total, 0)
    }
}
