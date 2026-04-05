import SwiftUI

struct SearchView: View {
    @EnvironmentObject var viewModel: SessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search stats
            if viewModel.isSearching {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Searching...")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("\(viewModel.searchResults.count) results for \"\(viewModel.searchQuery)\"")
                    }
                    Spacer()

                    Button("Clear") {
                        viewModel.clearSearch()
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            // Results list
            if viewModel.searchResults.isEmpty && viewModel.isSearching && !viewModel.isLoading {
                EmptyStateView(
                    title: "No Results",
                    systemImage: "magnifyingglass",
                    description: "No results for \"\(viewModel.searchQuery)\""
                )
            } else {
                List(selection: $viewModel.selectedSession) {
                    ForEach(viewModel.searchResults, id: \.0.id) { message, session in
                        if let session = session {
                            SearchResultDetailRow(message: message, session: session)
                                .tag(session)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct SearchResultDetailRow: View {
    let message: Message
    let session: Session

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Session info
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(session.displayName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Spacer()

                Text(dateFormatter.string(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Role indicator
                HStack(spacing: 6) {
                    Image(systemName: message.role == .user ? "person.fill" : "brain")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(message.role == .user ? .blue : .purple)
                    
                    Text(message.role.rawValue.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                }

                // Content preview
                Text(message.contentText)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    SearchView()
        .environmentObject(SessionViewModel())
}
