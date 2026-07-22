import Foundation

public struct HistogramBin: Sendable {
    public let rangeStartMM: Double
    public let rangeEndMM: Double
    public let count: Int
}

public struct ThicknessStatistics: Sendable {
    public let sampleCount: Int
    public let validSampleCount: Int
    public let averageMM: Double
    public let minimumMM: Double
    public let maximumMM: Double
    public let medianMM: Double
    public let standardDeviationMM: Double
    public let withinTolerancePercent: Double
    public let outOfTolerancePercent: Double
    public let coveragePercent: Double // validSampleCount / sampleCount
    public let histogram: [HistogramBin]

    public static let empty = ThicknessStatistics(
        sampleCount: 0, validSampleCount: 0, averageMM: 0, minimumMM: 0, maximumMM: 0,
        medianMM: 0, standardDeviationMM: 0, withinTolerancePercent: 0, outOfTolerancePercent: 0,
        coveragePercent: 0, histogram: []
    )

    public static func compute(
        samples: [ThicknessSample],
        desiredThicknessMM: Double,
        toleranceMM: Double,
        binCount: Int = 20
    ) -> ThicknessStatistics {
        let valid = samples.filter(\.isValid).map { Double($0.thicknessMM) }
        guard !valid.isEmpty else { return .empty }

        let sum = valid.reduce(0, +)
        let average = sum / Double(valid.count)
        let sorted = valid.sorted()
        let minimum = sorted.first!
        let maximum = sorted.last!
        let median: Double = {
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }()

        // Sample standard deviation (n-1 denominator) — the conventional choice
        // when reporting stats about a measured population rather than treating
        // this sample set as the entire population.
        let variance = valid.count > 1
            ? valid.reduce(0) { $0 + pow($1 - average, 2) } / Double(valid.count - 1)
            : 0
        let stdDev = sqrt(variance)

        let lowerBound = desiredThicknessMM - toleranceMM
        let upperBound = desiredThicknessMM + toleranceMM
        let withinCount = valid.filter { $0 >= lowerBound && $0 <= upperBound }.count
        let withinPercent = Double(withinCount) / Double(valid.count) * 100

        let histogram = buildHistogram(values: sorted, binCount: binCount)

        return ThicknessStatistics(
            sampleCount: samples.count,
            validSampleCount: valid.count,
            averageMM: average,
            minimumMM: minimum,
            maximumMM: maximum,
            medianMM: median,
            standardDeviationMM: stdDev,
            withinTolerancePercent: withinPercent,
            outOfTolerancePercent: 100 - withinPercent,
            coveragePercent: samples.isEmpty ? 0 : Double(valid.count) / Double(samples.count) * 100,
            histogram: histogram
        )
    }

    private static func buildHistogram(values: [Double], binCount: Int) -> [HistogramBin] {
        guard let lo = values.first, let hi = values.last, hi > lo, binCount > 0 else {
            return values.isEmpty ? [] : [HistogramBin(rangeStartMM: values[0], rangeEndMM: values[0], count: values.count)]
        }
        let width = (hi - lo) / Double(binCount)
        var counts = [Int](repeating: 0, count: binCount)
        for v in values {
            var bin = Int((v - lo) / width)
            if bin >= binCount { bin = binCount - 1 }
            if bin < 0 { bin = 0 }
            counts[bin] += 1
        }
        return (0..<binCount).map { i in
            HistogramBin(rangeStartMM: lo + Double(i) * width, rangeEndMM: lo + Double(i + 1) * width, count: counts[i])
        }
    }
}
