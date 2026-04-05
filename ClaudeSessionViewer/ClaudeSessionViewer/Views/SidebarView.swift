import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: SessionViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.projects.isEmpty {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.projects.isEmpty && !viewModel.isSearching {
                EmptyStateView(
                    title: "No Sessions Found",
                    systemImage: "folder.badge.questionmark",
                    description: "No Claude Code sessions found in ~/.claude/projects/"
                )
            } else {
                SidebarListView()
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250, idealWidth: 280)
        .layoutPriority(1)
    }
}

struct SidebarListView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @State private var expandedProjects: Set<String> = []

    var body: some View {
        List(selection: $viewModel.selectedSession) {
            if viewModel.isSearching {
                // Search results
                if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                    Section {
                        Text("No results for \"\(viewModel.searchQuery)\"")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                } else {
                    Section("Search Results") {
                        ForEach(viewModel.searchResults, id: \.0.id) { message, session in
                            if let session = session {
                                SearchResultRow(message: message, session: session)
                                    .tag(session)
                            }
                        }
                    }
                }
            } else {
                // Project list with collapsible sections
                ForEach(viewModel.projects) { project in
                    CollapsibleProjectSection(
                        project: project,
                        isExpanded: expandedProjects.contains(project.id),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedProjects.contains(project.id) {
                                    expandedProjects.remove(project.id)
                                } else {
                                    expandedProjects.insert(project.id)
                                }
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            // Expand all projects by default
            expandedProjects = Set(viewModel.projects.map(\.id))
        }
        .onChange(of: viewModel.projects) { newProjects in
            // Auto-expand new projects
            for project in newProjects {
                if !expandedProjects.contains(project.id) {
                    expandedProjects.insert(project.id)
                }
            }
        }
    }
}

struct CollapsibleProjectSection: View {
    let project: Project
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Section {
            if isExpanded {
                ForEach(project.sessions) { session in
                    SessionRow(session: session)
                        .tag(session)
                }
            }
        } header: {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(project.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .kerning(0.8)

                    Spacer()

                    Text("\(project.sessionCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .contextMenu {
                Button("Copy Folder Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(project.displayName, forType: .string)
                }
            }
        }
        .collapsible(false)
    }
}

struct SessionRow: View {
    let session: Session

    private var timeAgo: String {
        DateFormatters.relativeTimeAbbreviated.localizedString(for: session.lastUpdated, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary.opacity(0.9))

            HStack(spacing: 8) {
                Text(timeAgo)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "bubble.left")
                    Text("\(session.messageCount)")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Session Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.displayName, forType: .string)
            }
        }
    }
}

struct SearchResultRow: View {
    let message: Message
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: message.role == .user ? "person.fill" : "brain")
                    .foregroundStyle(message.role == .user ? .blue : .purple)
                    .font(.caption)

                Text(session.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message.contentText)
                .font(.body)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SidebarView()
        .environmentObject(SessionViewModel())
        .frame(width: 300)
}
