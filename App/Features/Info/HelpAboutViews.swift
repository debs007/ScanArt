import SwiftUI
import ScanArtUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingL) {
                helpSection(
                    title: "1. Create a Project",
                    icon: "folder.badge.plus",
                    text: "Set the desired plaster thickness and tolerance for the wall you're measuring. This drives the color legend and pass/fail statistics."
                )
                helpSection(
                    title: "2. Original Scan",
                    icon: "camera.metering.matrix",
                    text: "Before plastering, scan the bare wall. Move slowly and cover the whole area, including a bit of floor, ceiling, or a doorway if visible — these help align future rescans."
                )
                helpSection(
                    title: "3. Rescan After Plastering",
                    icon: "arrow.triangle.2.circlepath.camera",
                    text: "Once plaster is applied, start a rescan. Scan Art will try to relocalize to the exact position of the original scan — pan slowly around the room until alignment succeeds."
                )
                helpSection(
                    title: "4. Generate Thickness Map",
                    icon: "wand.and.rays",
                    text: "In Analysis, tap Generate Thickness Map. Scan Art compares both scans and colors the wall by how much thicker it grew — green means on target."
                )
                helpSection(
                    title: "5. Export & Report",
                    icon: "square.and.arrow.up",
                    text: "Export the colored mesh to DXF, OBJ, PLY, STL, USDZ, CSV, or JSON, or generate a PDF report to share with your client or team."
                )

                Divider().background(ScanArtTheme.surfaceBorder)

                helpSection(
                    title: "Tips for Best Results",
                    icon: "lightbulb.fill",
                    text: "Scan in good, even lighting. Avoid scanning highly reflective or completely blank surfaces. Keep the device moving slowly and steadily — quick motions can lose tracking."
                )
            }
            .padding(ScanArtTheme.spacingL)
        }
        .scanArtScreenBackground()
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpSection(title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: ScanArtTheme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(ScanArtTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(ScanArtTheme.title(16)).foregroundStyle(ScanArtTheme.textPrimary)
                Text(text).font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textSecondary)
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                    .padding(.top, ScanArtTheme.spacingL)

                Text("Scan Art").font(ScanArtTheme.numericDisplay(26)).foregroundStyle(ScanArtTheme.textPrimary)
                Text(appVersionString).font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textSecondary)

                Text("LiDAR-based plaster thickness measurement for civil engineers, architects, and contractors. Every scan, measurement, and report stays on this device — Scan Art works entirely offline.")
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ScanArtTheme.spacingL)

                VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
                    aboutRow("Alignment", "ARKit world-map relocalization + ICP refinement")
                    aboutRow("Measurement", "Ray-mesh intersection thickness sampling")
                    aboutRow("Storage", "100% on-device, no account or cloud required")
                }
                .padding(ScanArtTheme.spacingM)
                .glassPanel()
                .padding(.horizontal, ScanArtTheme.spacingL)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, ScanArtTheme.spacingXL)
        }
        .scanArtScreenBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(ScanArtTheme.label()).foregroundStyle(ScanArtTheme.textTertiary).frame(width: 90, alignment: .leading)
            Text(value).font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textPrimary)
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "Version \(version)"
    }
}
