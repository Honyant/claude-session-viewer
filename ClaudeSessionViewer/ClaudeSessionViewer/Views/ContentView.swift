import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            Group {
                if let session = viewModel.selectedSession {
                    ConversationView(session: session)
                } else {
                    EmptyStateView(
                        title: "Select a Session",
                        systemImage: "bubble.left.and.bubble.right",
                        description: "Choose a session from the sidebar to view its conversation"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: "Search conversations..."
        )
        .onChange(of: searchText) { newValue in
            searchTask?.cancel()

            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                viewModel.clearSearch()
                return
            }

            guard newValue.count >= 2 else { return }

            searchTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    viewModel.searchQuery = newValue
                    Task { await viewModel.performSearch() }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Refreshing sessions…")
                } else {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh sessions (Cmd+R)")
                }
            }
        }
        .task {
            await viewModel.initialize()
        }
    }
}

/// A reusable empty state view for macOS 13 compatibility
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionViewModel())
}
