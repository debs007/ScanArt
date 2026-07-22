import SwiftUI
import ScanArtAlgorithms

/// Generic glass-panel container for grouping content on top of AR/3D views.
public struct GlassCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(ScanArtTheme.spacingM)
            .glassPanel()
    }
}

/// Large, thumb-friendly primary action button — "large buttons, one-handed
/// operation" from the spec's UI Design section.
public struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let isDestructive: Bool
    let isEnabled: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isDestructive: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: ScanArtTheme.spacingS) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(ScanArtTheme.title(17))
            }
            .frame(maxWidth: .infinity)
            .frame(height: ScanArtTheme.minTouchTarget)
            .foregroundStyle(isEnabled ? Color.black.opacity(0.9) : ScanArtTheme.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                    .fill(isEnabled ? (isDestructive ? ScanArtTheme.statusDanger : ScanArtTheme.accent) : ScanArtTheme.surfaceElevated)
            )
        }
        .disabled(!isEnabled)
    }
}

public struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: ScanArtTheme.spacingS) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(ScanArtTheme.body(16))
            }
            .frame(maxWidth: .infinity)
            .frame(height: ScanArtTheme.minTouchTarget)
            .foregroundStyle(ScanArtTheme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                    .stroke(ScanArtTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }
}

/// A single statistic tile for the Analysis screen's stats grid (average,
/// min, max, median, std dev, volume, area, coverage, tolerance %).
public struct StatCard: View {
    let label: String
    let value: String
    let unit: String?
    let tint: Color

    public init(label: String, value: String, unit: String? = nil, tint: Color = ScanArtTheme.textPrimary) {
        self.label = label
        self.value = value
        self.unit = unit
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingXS) {
            Text(label.uppercased())
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(ScanArtTheme.numericDisplay(24))
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(ScanArtTheme.body(13))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ScanArtTheme.spacingM)
        .background(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous).fill(ScanArtTheme.surfaceElevated))
    }
}

/// Floating color-band legend, shown during live scanning and in the
/// Analysis viewer — the spec's "Live Legend" section.
public struct ThicknessLegendView: View {
    let stops: [ColorStop]
    let unit: (Double) -> String

    public init(stops: [ColorStop], unit: @escaping (Double) -> String = { String(format: "%.0fmm", $0) }) {
        self.stops = stops
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingXS) {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                HStack(spacing: ScanArtTheme.spacingS) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b))
                        .frame(width: 16, height: 16)
                    Text(stop.label)
                        .font(ScanArtTheme.body(12))
                        .foregroundStyle(ScanArtTheme.textPrimary)
                }
            }
        }
        .padding(ScanArtTheme.spacingS)
        .glassPanel(cornerRadius: ScanArtTheme.radiusS)
    }
}

/// Circular coverage-percentage indicator shown during live scanning.
public struct CoverageRing: View {
    let percent: Double
    public init(percent: Double) { self.percent = percent }

    public var body: some View {
        ZStack {
            Circle().stroke(ScanArtTheme.surfaceElevated, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(percent / 100, 0), 1))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent))%")
                .font(ScanArtTheme.monospacedValue(14))
                .foregroundStyle(ScanArtTheme.textPrimary)
        }
        .frame(width: 56, height: 56)
        .animation(.easeOut(duration: 0.25), value: percent)
    }

    private var ringColor: Color {
        switch percent {
        case ..<40: return ScanArtTheme.statusDanger
        case 40..<75: return ScanArtTheme.statusWarning
        default: return ScanArtTheme.statusGood
        }
    }
}
