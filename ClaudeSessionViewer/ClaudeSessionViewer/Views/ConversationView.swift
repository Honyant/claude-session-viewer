import SwiftUI

struct SessionHeaderView: View {
    let session: Session
    var messages: [Message] = []
    @State private var showingInfo = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var fileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: session.fileSize)
    }

    private func copyAllMessages() {
        let formatted = messages
            .filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { message -> String in
                let role = message.role == .user ? "You" : "Claude"
                return "\(role):\n\(message.contentText)"
            }
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.displayName, forType: .string)
                        }

                    if let cwd = session.cwd {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(cwd)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(.secondary.opacity(0.8))
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cwd, forType: .string)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(dateFormatter.string(from: session.startTime))
                            .font(.system(size: 10, weight: .medium))

                        Text("\(session.messageCount) messages")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary.opacity(0.7))

                    // Copy All button
                    Button(action: copyAllMessages) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy entire conversation")
                    .disabled(messages.isEmpty)

                    Button {
                        showingInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Session Details")
                                .font(.headline)

                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Text("Session ID:")
                                        .foregroundStyle(.secondary)
                                    Text(session.id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                GridRow {
                                    Text("File:")
                                        .foregroundStyle(.secondary)
                                    Text(session.filePath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                GridRow {
                                    Text("Size:")
                                        .foregroundStyle(.secondary)
                                    Text(fileSize)
                                }
                                GridRow {
                                    Text("Started:")
                                        .foregroundStyle(.secondary)
                                    Text(dateFormatter.string(from: session.startTime))
                                }
                                GridRow {
                                    Text("Last Updated:")
                                        .foregroundStyle(.secondary)
                                    Text(dateFormatter.string(from: session.lastUpdated))
                                }
                            }
                            .font(.system(size: 12))

                            Divider()

                            Button("Open in Finder") {
                                NSWorkspace.shared.selectFile(session.filePath, inFileViewerRootedAtPath: "")
                                showingInfo = false
                            }
                            .buttonStyle(.link)
                        }
                        .padding()
                        .frame(minWidth: 300)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()
        }
    }
}

struct ConversationView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    let session: Session
    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showSearchBar = false
    @FocusState private var isSearchFocused: Bool

    // Filter out empty messages and apply search
    private var displayMessages: [Message] {
        let nonEmpty = messages.filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if searchText.isEmpty {
            return nonEmpty
        }
        let query = searchText.lowercased()
        return nonEmpty.filter { $0.contentText.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SessionHeaderView(session: session, messages: messages)

            // Search bar (shown on Cmd+F)
            if showSearchBar {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search in session...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)

                    if !searchText.isEmpty {
                        Text("\(displayMessages.count) results")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSearchBar = false
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.primary.opacity(0.1)),
                    alignment: .bottom
                )
            }

            // Messages
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                EmptyStateView(
                    title: "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: "This session has no messages"
                )
            } else if displayMessages.isEmpty {
                EmptyStateView(
                    title: "No Matches",
                    systemImage: "magnifyingglass",
                    description: "No messages match \"\(searchText)\""
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayMessages) { message in
                                MessageBubble(message: message, highlightText: searchText)
                                    .id(message.id)
                                    .padding(.horizontal, 24)

                                if message.id != displayMessages.last?.id {
                                    Divider()
                                        .padding(.leading, 58)
                                        .opacity(0.3)
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onAppear {
                        if let lastMessage = displayMessages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .focusSessionSearch)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showSearchBar = true
            }
            // Delay focus to allow animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .task(id: session.id) {
            await loadMessages()
        }
        .onChange(of: session.id) { _ in
            searchText = ""
            showSearchBar = false
        }
        .onExitCommand {
            if showSearchBar {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSearchBar = false
                    searchText = ""
                }
            }
        }
    }

    private func loadMessages() async {
        isLoading = true
        messages = await viewModel.loadMessages(for: session)
        isLoading = false
    }
}

#Preview {
    ConversationView(session: Session(
        id: "test",
        slug: "Test Session",
        projectPath: "-Users-test-project",
        cwd: "/Users/test/project",
        startTime: Date(),
        lastUpdated: Date(),
        messageCount: 5,
        filePath: "/path/to/file",
        fileMtime: Date(),
        fileSize: 1000
    ))
    .environmentObject(SessionViewModel())
}
