import Foundation

public struct RGBAColor: Sendable, Codable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static func lerp(_ x: RGBAColor, _ y: RGBAColor, _ t: Double) -> RGBAColor {
        RGBAColor(
            r: x.r + (y.r - x.r) * t,
            g: x.g + (y.g - x.g) * t,
            b: x.b + (y.b - x.b) * t,
            a: x.a + (y.a - x.a) * t
        )
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

public struct ColorStop: Sendable, Codable {
    public var thicknessMM: Double
    public var color: RGBAColor
    public var label: String

    public init(thicknessMM: Double, color: RGBAColor, label: String) {
        self.thicknessMM = thicknessMM
        self.color = color
        self.label = label
    }
}

/// Maps a thickness value to a color, using piecewise-linear interpolation
/// between an ascending list of stops. Bands are defined relative to the
/// project's desired thickness + tolerance, matching the spec's example:
/// desired 4cm, tolerance +/-0.2cm -> green 3.8-4.2, yellow 4.2-5, red 5+,
/// blue below 3.8 — extended with the fuller 7-band palette from the spec's
/// "Color Representation" section for more resolution in the 3D viewer and
/// DXF layer coloring.
public struct ThicknessColorMapper: Sendable, Codable {
    public var stops: [ColorStop] // must be sorted ascending by thicknessMM

    public init(stops: [ColorStop]) {
        self.stops = stops.sorted { $0.thicknessMM < $1.thicknessMM }
    }

    public func color(for thicknessMM: Double) -> RGBAColor {
        guard let first = stops.first else { return RGBAColor(r: 1, g: 1, b: 1) }
        guard let last = stops.last else { return first.color }
        if thicknessMM <= first.thicknessMM { return first.color }
        if thicknessMM >= last.thicknessMM { return last.color }
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if thicknessMM >= a.thicknessMM && thicknessMM <= b.thicknessMM {
                let t = (thicknessMM - a.thicknessMM) / (b.thicknessMM - a.thicknessMM)
                return RGBAColor.lerp(a.color, b.color, t)
            }
        }
        return last.color
    }

    /// Invalid / no-data samples render as a neutral gray so holes in the rescan
    /// are visually distinct from "very thin" (dark blue) rather than confusable.
    public static let noData = RGBAColor(r: 0.35, g: 0.35, b: 0.38, a: 0.6)

    /// The default 7-band palette described in the spec, scaled to a project's
    /// desired thickness and tolerance.
    public static func standard(desiredThicknessMM: Double, toleranceMM: Double) -> ThicknessColorMapper {
        let lower = desiredThicknessMM - toleranceMM
        let upper = desiredThicknessMM + toleranceMM
        // 20 % over-application threshold — only meaningful when it falls above the
        // tolerance upper bound (i.e. tolerance < 20 % of target, which is typical).
        let overApplication = max(upper * 1.01, desiredThicknessMM * 1.2)
        return ThicknessColorMapper(stops: [
            ColorStop(thicknessMM: 0,               color: RGBAColor(r: 0.05, g: 0.05, b: 0.45), label: "Very thin"),
            ColorStop(thicknessMM: lower * 0.6,     color: RGBAColor(r: 0.10, g: 0.35, b: 0.95), label: "Below target"),
            ColorStop(thicknessMM: lower,            color: RGBAColor(r: 0.10, g: 0.80, b: 0.35), label: "Within tolerance"),
            ColorStop(thicknessMM: desiredThicknessMM, color: RGBAColor(r: 0.20, g: 0.85, b: 0.30), label: "On target"),
            ColorStop(thicknessMM: upper,            color: RGBAColor(r: 0.95, g: 0.85, b: 0.15), label: "Slightly thick"),
            ColorStop(thicknessMM: overApplication,  color: RGBAColor(r: 0.95, g: 0.45, b: 0.05), label: "Over-application (20%)"),
            ColorStop(thicknessMM: upper * 1.5,     color: RGBAColor(r: 0.90, g: 0.15, b: 0.15), label: "Very thick"),
            ColorStop(thicknessMM: upper * 2.0,     color: RGBAColor(r: 0.55, g: 0.15, b: 0.75), label: "Extremely thick")
        ])
    }

    /// Simplified 4-band palette for the floating live legend during scanning.
    public static func liveLegend(desiredThicknessMM: Double, toleranceMM: Double) -> [ColorStop] {
        let lower = desiredThicknessMM - toleranceMM
        let upper = desiredThicknessMM + toleranceMM
        return [
            ColorStop(thicknessMM: 0, color: RGBAColor(r: 0.10, g: 0.35, b: 0.95), label: "0 – \(Int(lower))"),
            ColorStop(thicknessMM: lower, color: RGBAColor(r: 0.10, g: 0.80, b: 0.35), label: "\(Int(lower)) – \(Int(upper))"),
            ColorStop(thicknessMM: upper, color: RGBAColor(r: 0.95, g: 0.85, b: 0.15), label: "\(Int(upper)) – \(Int(upper * 1.3))"),
            ColorStop(thicknessMM: upper * 1.3, color: RGBAColor(r: 0.90, g: 0.15, b: 0.15), label: "\(Int(upper * 1.3))+")
        ]
    }
}
