import Foundation
import SwiftUI

@MainActor
class SessionViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedSession: Session?
    @Published var searchQuery: String = ""
    @Published var searchResults: [(Message, Session?)] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isSearching = false
    @Published var errorMessage: String?

    private let database = SessionDatabase()
    private let parser = SessionParser()
    private var scanner: SessionScanner?
    private var isScanning = false

    var isInitialized = false

    func initialize() async {
        guard !isInitialized else { return }
        isInitialized = true

        do {
            try await database.initialize()
            scanner = SessionScanner(database: database, parser: parser)

            // Phase 1: Load cached sessions from DB immediately.
            let cached = try await database.fetchAllSessions()

            if cached.isEmpty {
                // First-ever launch — show spinner while we do the initial scan.
                isLoading = true
                defer { isLoading = false }

                let sessions = try await runScan()
                projects = Project.groupSessions(sessions)
            } else {
                // Subsequent launch — render from cache instantly, scan in background.
                projects = Project.groupSessions(cached)
                startBackgroundScan()
            }

            // Start watching for changes
            scanner?.startWatching { [weak self] in
                Task { @MainActor [weak self] in
                    self?.startBackgroundScan()
                }
            }

            let stats = try await database.getStats()
            print("Loaded \(stats.sessionCount) sessions with \(stats.messageCount) messages")
        } catch {
            isLoading = false
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            print("Initialization error: \(error)")
        }
    }

    func refresh() {
        startBackgroundScan()
    }

    private func startBackgroundScan() {
        guard !isScanning, let scanner else { return }
        isScanning = true
        isRefreshing = true

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let sessions = try await scanner.scanAndIndex()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.projects = Project.groupSessions(sessions)
                    // Update selected session if it still exists
                    if let selected = self.selectedSession {
                        self.selectedSession = sessions.first { $0.id == selected.id }
                    }
                    self.isScanning = false
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.errorMessage = "Failed to refresh: \(error.localizedDescription)"
                    print("Refresh error: \(error)")
                    self.isScanning = false
                    self.isRefreshing = false
                }
            }
        }
    }

    /// Run a scan synchronously (used for first-ever launch).
    private func runScan() async throws -> [Session] {
        guard let scanner else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try await scanner.scanAndIndex()
        }.value
    }

    func loadMessages(for session: Session) async -> [Message] {
        do {
            return try await database.fetchMessages(forSession: session.id)
        } catch {
            print("Error loading messages: \(error)")
            return []
        }
    }

    func performSearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }

        // Capture the query so older searches don't overwrite newer results,
        // and so older tasks don't turn off the loading indicator prematurely.
        let querySnapshot = trimmed

        isSearching = true
        isLoading = true

        do {
            let results = try await database.searchMessages(query: querySnapshot)

            // Only publish results if the query hasn't changed while we were searching.
            guard querySnapshot == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = results
        } catch {
            print("Search error: \(error)")
            guard querySnapshot == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = []
        }

        // Only clear the loading spinner if this search is still the active one.
        if querySnapshot == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
            isLoading = false
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }
}
