import SwiftUI
import UIKit
import ScanArtCore
import ScanArtAlgorithms
import ScanArtUI

// MARK: - Editable stop model

private struct EditableStop {
    /// Threshold value in the project's display unit (cm / mm / in).
    var thresholdDisplay: Double
    var color: Color
    var label: String
    /// Band 0 is always clamped to 0 — threshold not editable.
    let isFirst: Bool
}

// MARK: - View

/// Sheet that lets the user customize both the color and the start threshold
/// of each heatmap band. Defaults are seeded from the project's
/// desiredThicknessMM / toleranceMM and saved back to customColorStopsJSON.
struct ColorPaletteEditorView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var stops: [EditableStop] = []
    /// Tracks which row's threshold field is active so we validate on commit.
    @FocusState private var focusedIndex: Int?

    private var unitLabel: String { project.unit.rawValue }
    // Stepper increment: 0.5 cm expressed in the project's display unit
    private var stepSize: Double { project.unit.fromMillimeters(5.0) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewSection
                    .padding(.horizontal, ScanArtTheme.spacingL)
                    .padding(.top, ScanArtTheme.spacingM)
                    .padding(.bottom, ScanArtTheme.spacingS)

                Divider().background(ScanArtTheme.surfaceBorder)

                bandList
            }
            .scanArtScreenBackground()
            .navigationTitle("Color Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ScanArtTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(ScanArtTheme.accent)
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { focusedIndex = nil }
                }
            }
            .onAppear { loadStops() }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
            Text("GRADIENT PREVIEW")
                .font(ScanArtTheme.label())
                .foregroundStyle(ScanArtTheme.textTertiary)

            proportionalGradientBar
                .frame(height: 48)

            // Threshold ruler labels
            thresholdRuler

            HStack {
                if project.hasCustomColors {
                    Button("Reset to Default") {
                        project.resetCustomColors()
                        loadStops()
                    }
                    .font(ScanArtTheme.body(13))
                    .foregroundStyle(ScanArtTheme.statusDanger)
                }
                Spacer()
                Text("\(stops.count) bands")
                    .font(ScanArtTheme.body(12))
                    .foregroundStyle(ScanArtTheme.textTertiary)
            }
        }
    }

    /// Gradient where each color stop is positioned proportionally to its
    /// threshold, giving a realistic preview of how the heatmap will look.
    private var proportionalGradientBar: some View {
        let gradStops = proportionalGradientStops()
        return LinearGradient(stops: gradStops, startPoint: .leading, endPoint: .trailing)
            .clipShape(RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScanArtTheme.radiusM, style: .continuous)
                    .stroke(ScanArtTheme.surfaceBorder, lineWidth: 1)
            )
    }

    private var thresholdRuler: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    let fraction = normalizedPosition(index: index)
                    Text(index == 0 ? "0" : formatted(stop.thresholdDisplay))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ScanArtTheme.textSecondary)
                        .position(x: fraction * geo.size.width, y: 8)
                }
            }
        }
        .frame(height: 16)
    }

    // MARK: - Band list

    private var bandList: some View {
        List {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                bandRow(index: index)
                    .listRowBackground(ScanArtTheme.surfaceElevated)
                    .listRowSeparatorTint(ScanArtTheme.surfaceBorder)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ScanArtTheme.backgroundPrimary)
    }

    private func bandRow(index: Int) -> some View {
        HStack(spacing: ScanArtTheme.spacingM) {
            // Color picker
            ColorPicker("", selection: $stops[index].color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36, height: 36)

            // Name + threshold
            VStack(alignment: .leading, spacing: 4) {
                Text(stops[index].label)
                    .font(ScanArtTheme.body(15))
                    .foregroundStyle(ScanArtTheme.textPrimary)

                HStack(spacing: 4) {
                    Text("≥")
                        .font(ScanArtTheme.body(13))
                        .foregroundStyle(ScanArtTheme.textTertiary)

                    if stops[index].isFirst {
                        // Band 0 is always 0 — show locked value
                        Text("0 \(unitLabel)")
                            .font(ScanArtTheme.monospacedValue(13))
                            .foregroundStyle(ScanArtTheme.textTertiary)
                    } else {
                        // Stepper buttons (±0.5 cm) flanking the text field
                        Button {
                            stops[index].thresholdDisplay = max(0, stops[index].thresholdDisplay - stepSize)
                            clampThreshold(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(ScanArtTheme.textSecondary)
                        }
                        .buttonStyle(.plain)

                        TextField("0",
                                  value: $stops[index].thresholdDisplay,
                                  format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .font(ScanArtTheme.monospacedValue(13))
                            .foregroundStyle(ScanArtTheme.textPrimary)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedIndex, equals: index)
                            .onChange(of: focusedIndex) { old, new in
                                if old == index, new != index { clampThreshold(at: index) }
                            }

                        Button {
                            stops[index].thresholdDisplay += stepSize
                            clampThreshold(at: index)
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(ScanArtTheme.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Text(unitLabel)
                            .font(ScanArtTheme.body(13))
                            .foregroundStyle(ScanArtTheme.textSecondary)
                    }
                }
            }

            Spacer()

            // Live color swatch
            RoundedRectangle(cornerRadius: ScanArtTheme.radiusS)
                .fill(stops[index].color)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: ScanArtTheme.radiusS)
                        .stroke(ScanArtTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .padding(.vertical, ScanArtTheme.spacingXS)
    }

    // MARK: - Data helpers

    private func loadStops() {
        let mapper = project.colorMapper()
        stops = mapper.stops.enumerated().map { index, stop in
            EditableStop(
                thresholdDisplay: project.unit.fromMillimeters(stop.thicknessMM),
                color: Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b),
                label: stop.label,
                isFirst: index == 0
            )
        }
    }

    private func save() {
        focusedIndex = nil  // commit any active field
        let colorStops = stops.map { stop -> ColorStop in
            let threshMM = project.unit.toMillimeters(stop.thresholdDisplay)
            let ui = UIColor(stop.color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return ColorStop(
                thicknessMM: threshMM,
                color: RGBAColor(r: Double(r), g: Double(g), b: Double(b), a: Double(a)),
                label: stop.label
            )
        }
        project.saveCustomStops(colorStops)
    }

    /// Ensures stop[index].thresholdDisplay stays strictly between its neighbors.
    private func clampThreshold(at index: Int) {
        guard index > 0, index < stops.count else { return }
        let minDisplay: Double
        let maxDisplay: Double
        let epsilon = project.unit.fromMillimeters(0.5)  // 0.5 mm gap minimum

        if index > 0 {
            minDisplay = stops[index - 1].thresholdDisplay + epsilon
        } else {
            minDisplay = 0
        }
        if index < stops.count - 1 {
            maxDisplay = stops[index + 1].thresholdDisplay - epsilon
        } else {
            maxDisplay = .infinity
        }

        let clamped = min(max(stops[index].thresholdDisplay, minDisplay), maxDisplay)
        if clamped != stops[index].thresholdDisplay {
            stops[index].thresholdDisplay = clamped
        }
    }

    // MARK: - Gradient positioning

    private func proportionalGradientStops() -> [Gradient.Stop] {
        guard stops.count > 1 else {
            return stops.map { Gradient.Stop(color: $0.color, location: 0) }
        }
        let maxDisplay = stops.last!.thresholdDisplay
        guard maxDisplay > 0 else {
            return stops.enumerated().map { i, s in
                Gradient.Stop(color: s.color, location: Double(i) / Double(stops.count - 1))
            }
        }
        return stops.map { stop in
            Gradient.Stop(color: stop.color, location: min(stop.thresholdDisplay / maxDisplay, 1.0))
        }
    }

    private func normalizedPosition(index: Int) -> Double {
        guard stops.count > 1 else { return 0 }
        let maxDisplay = stops.last!.thresholdDisplay
        guard maxDisplay > 0 else {
            return Double(index) / Double(stops.count - 1)
        }
        return min(stops[index].thresholdDisplay / maxDisplay, 1.0)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
