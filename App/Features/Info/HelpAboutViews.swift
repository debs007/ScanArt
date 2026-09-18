import SwiftUI
import ScanArtUI

struct HelpView: View {
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScanArtTheme.spacingL) {
                helpSection(
                    title: l10n("help.1.title"),
                    icon: "folder.badge.plus",
                    text: l10n("help.1.text")
                )
                helpSection(
                    title: l10n("help.2.title"),
                    icon: "camera.metering.matrix",
                    text: l10n("help.2.text")
                )
                helpSection(
                    title: l10n("help.3.title"),
                    icon: "arrow.triangle.2.circlepath.camera",
                    text: l10n("help.3.text")
                )
                helpSection(
                    title: l10n("help.4.title"),
                    icon: "wand.and.rays",
                    text: l10n("help.4.text")
                )
                helpSection(
                    title: l10n("help.5.title"),
                    icon: "square.and.arrow.up",
                    text: l10n("help.5.text")
                )

                Divider().background(ScanArtTheme.surfaceBorder)

                helpSection(
                    title: l10n("help.tips.title"),
                    icon: "lightbulb.fill",
                    text: l10n("help.tips.text")
                )
            }
            .padding(ScanArtTheme.spacingL)
        }
        .scanArtScreenBackground()
        .navigationTitle(l10n("help.title"))
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
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(spacing: ScanArtTheme.spacingL) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(ScanArtTheme.accent)
                    .padding(.top, ScanArtTheme.spacingL)

                Text(l10n("app.name")).font(ScanArtTheme.numericDisplay(26)).foregroundStyle(ScanArtTheme.textPrimary)
                Text(appVersionString).font(ScanArtTheme.body(13)).foregroundStyle(ScanArtTheme.textSecondary)

                Text(l10n("about.subtitle"))
                    .font(ScanArtTheme.body(14))
                    .foregroundStyle(ScanArtTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ScanArtTheme.spacingL)

                VStack(alignment: .leading, spacing: ScanArtTheme.spacingS) {
                    aboutRow(l10n("about.alignment"), l10n("about.alignment.value"))
                    aboutRow(l10n("about.measurement"), l10n("about.measurement.value"))
                    aboutRow(l10n("about.storage"), l10n("about.storage.value"))
                }
                .padding(ScanArtTheme.spacingM)
                .glassPanel()
                .padding(.horizontal, ScanArtTheme.spacingL)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, ScanArtTheme.spacingXL)
        }
        .scanArtScreenBackground()
        .navigationTitle(l10n("about.title"))
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
        return "\(l10n("settings.version")) \(version)"
    }
}
