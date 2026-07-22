import SwiftUI
import ScanArtCore
import ScanArtUI

struct ProjectListView: View {
    @Binding var path: NavigationPath
    @Binding var isCreatingProject: Bool
    @Environment(\.diContainer) private var di

    @State private var projects: [Project] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: ScanArtTheme.spacingS) {
                if projects.isEmpty {
                    emptyState
                } else {
                    ForEach(projects) { project in
                        Button {
                            path.append(AppRoute.projectDetail(projectID: project.id))
                        } label: {
                            ProjectRow(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(ScanArtTheme.spacingM)
        }
        .scanArtScreenBackground()
        .navigationTitle("Projects")
        .searchable(text: $searchText, prompt: "Search by name, customer, site, engineer")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: searchText) { _, _ in reload() }
        .task { reload() }
        .onAppear { reload() }
    }

    private var emptyState: some View {
        VStack(spacing: ScanArtTheme.spacingM) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(ScanArtTheme.textTertiary)
            Text(searchText.isEmpty ? "No projects yet" : "No matching projects")
                .font(ScanArtTheme.body(15))
                .foregroundStyle(ScanArtTheme.textSecondary)
        }
        .padding(.top, ScanArtTheme.spacingXL)
    }

    private func reload() {
        guard let di else { return }
        do {
            projects = try di.projectRepository.searchProjects(query: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
