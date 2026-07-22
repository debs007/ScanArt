import SwiftUI

/// The spec's UI direction: "professional construction software, dark theme,
/// minimal, industrial colors, glass effects, large buttons, one-handed
/// operation." This is the single source of truth for that language so every
/// screen pulls from the same palette instead of hardcoding colors.
public enum ScanArtTheme {
    // MARK: - Surfaces (deep, desaturated — reads as tool, not toy)
    public static let backgroundPrimary = Color(red: 0.055, green: 0.063, blue: 0.078)
    public static let backgroundSecondary = Color(red: 0.086, green: 0.098, blue: 0.118)
    public static let surfaceElevated = Color(red: 0.118, green: 0.133, blue: 0.157)
    public static let surfaceBorder = Color.white.opacity(0.08)

    // MARK: - Accent — a single confident "safety" amber/orange, matching
    // industrial equipment and hi-vis site signage rather than a generic app blue.
    public static let accent = Color(red: 0.95, green: 0.58, blue: 0.16)
    public static let accentMuted = Color(red: 0.95, green: 0.58, blue: 0.16).opacity(0.18)

    // MARK: - Semantic (mirrors the thickness palette so status colors feel
    // consistent with the measurement heat map elsewhere in the app)
    public static let statusGood = Color(red: 0.20, green: 0.85, blue: 0.30)
    public static let statusWarning = Color(red: 0.95, green: 0.85, blue: 0.15)
    public static let statusDanger = Color(red: 0.90, green: 0.20, blue: 0.20)
    public static let statusInfo = Color(red: 0.30, green: 0.60, blue: 0.95)

    // MARK: - Text
    public static let textPrimary = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.62)
    public static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Spacing (8pt grid)
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32

    // MARK: - Radii — large-buttons/one-handed-use direction reads as
    // generous corner radii, not sharp technical-drawing edges.
    public static let radiusS: CGFloat = 8
    public static let radiusM: CGFloat = 14
    public static let radiusL: CGFloat = 22

    // MARK: - Minimum touch target, per HIG, sized up for gloved/on-site use.
    public static let minTouchTarget: CGFloat = 52

    // MARK: - Typography — a tight, technical type scale. System font at
    // weight extremes (heavy for numbers/headers, regular for body) reads as
    // "instrument panel" without needing a licensed display face.
    public static func numericDisplay(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    public static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    public static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    public static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .default).uppercaseSmallCaps()
    }
    public static func monospacedValue(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

/// The spec's "glass effects" — a translucent, blurred material for cards and
/// panels floating over the AR camera feed or 3D viewer.
public struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = ScanArtTheme.radiusM
    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ScanArtTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

public extension View {
    func glassPanel(cornerRadius: CGFloat = ScanArtTheme.radiusM) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    /// Applies the app's dark background + preferred color scheme in one call,
    /// used at each screen's root.
    func scanArtScreenBackground() -> some View {
        self
            .background(ScanArtTheme.backgroundPrimary.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
