import Foundation

/// Scans for Claude Code session files and watches for changes.
///
/// Optimizations:
/// - Batches the "does this file need reindexing?" checks into a single database read.
/// - Indexes files in parallel with a bounded level of concurrency.
/// - Debounces filesystem events so rapid writes don't trigger repeated full rescans.
final class SessionScanner: @unchecked Sendable {
    private let claudeProjectsPath: URL
    private let database: SessionDatabase
    private let parser: SessionParser

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedDirectoryFD: Int32 = -1
    private var onSessionsChanged: (() -> Void)?
    private var pendingChangeWorkItem: DispatchWorkItem?
    private let lock = NSLock()

    /// Debounce interval for filesystem events.
    private let debounceDelay: TimeInterval = 0.5

    init(database: SessionDatabase, parser: SessionParser) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.claudeProjectsPath = homeDir.appendingPathComponent(".claude/projects", isDirectory: true)
        self.database = database
        self.parser = parser
    }

    /// Scan all session files and index them.
    func scanAndIndex() async throws -> [Session] {
        let sessionFiles = try discoverSessionFiles()

        // Single read of existing indexing metadata to avoid one DB query per file.
        let existingIndex = try await database.fetchSessionFileIndex()

        // Determine which files need indexing.
        let filesToIndex = sessionFiles.filter { fileInfo in
            guard let existing = existingIndex[fileInfo.path] else { return true }
            return existing.mtime != fileInfo.mtime || existing.size != fileInfo.size
        }

        var didChange = false

        // Parse/index in parallel, but limit concurrency so we don't spawn thousands of tasks at once.
        let maxConcurrent = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))

        struct IndexedSession {
            let session: Session
            let messages: [Message]
        }

        await withTaskGroup(of: IndexedSession?.self) { group in
            var iterator = filesToIndex.makeIterator()

            func submitNext() {
                guard let fileInfo = iterator.next() else { return }

                group.addTask { [parser] in
                    autoreleasepool {
                        do {
                            let parsed = try parser.parse(fileAt: fileInfo.url)

                            let session = Session(
                                id: parsed.sessionId,
                                slug: parsed.slug,
                                projectPath: fileInfo.projectPath,
                                cwd: parsed.cwd,
                                startTime: parsed.startTime,
                                lastUpdated: parsed.lastUpdated,
                                messageCount: parsed.messages.count,
                                filePath: fileInfo.path,
                                fileMtime: fileInfo.mtime,
                                fileSize: fileInfo.size
                            )

                            return IndexedSession(session: session, messages: parsed.messages)
                        } catch {
                            print("Error processing \(fileInfo.path): \(error)")
                            return nil
                        }
                    }
                }
            }

            // Prime the task group.
            for _ in 0..<maxConcurrent {
                submitNext()
            }

            // As each task completes, write results to the database and submit the next task.
            while let result = await group.next() {
                if let indexed = result {
                    do {
                        try await database.save(session: indexed.session, messages: indexed.messages)
                        didChange = true
                    } catch {
                        print("Error saving \(indexed.session.filePath): \(error)")
                    }
                }
                submitNext()
            }
        }

        // Cleanup orphaned sessions (deleted/renamed files).
        // Reuse `existingIndex` to avoid a redundant DB query.
        let existingPaths = Set(sessionFiles.map(\.path))
        let orphanedIds = existingIndex
            .filter { !existingPaths.contains($0.key) }
            .map { $0.value.id }
        if !orphanedIds.isEmpty {
            try await database.deleteSessions(ids: orphanedIds)
            didChange = true
        }

        // Optimize query planner only if anything changed.
        if didChange {
            try await database.runAnalyze()
        }

        // Return all sessions from database.
        return try await database.fetchAllSessions()
    }

    /// Start watching for file changes.
    func startWatching(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        self.onSessionsChanged = onChange

        guard FileManager.default.fileExists(atPath: claudeProjectsPath.path) else {
            print("Claude projects directory not found: \(claudeProjectsPath.path)")
            return
        }

        watchedDirectoryFD = open(claudeProjectsPath.path, O_EVTONLY)
        guard watchedDirectoryFD >= 0 else {
            print("Failed to open directory for watching")
            return
        }

        let fd = watchedDirectoryFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let callback = self.onSessionsChanged

            // Debounce: cancel any pending callback and schedule a new one.
            self.pendingChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                callback?()
            }
            self.pendingChangeWorkItem = workItem
            self.lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.debounceDelay, execute: workItem)
        }

        source.setCancelHandler { [weak self] in
            if fd >= 0 {
                close(fd)
            }
            self?.watchedDirectoryFD = -1
        }

        fileWatcher = source
        source.resume()
    }

    /// Stop watching for changes.
    func stopWatching() {
        lock.lock()
        defer { lock.unlock() }

        pendingChangeWorkItem?.cancel()
        pendingChangeWorkItem = nil

        fileWatcher?.cancel()
        fileWatcher = nil
    }

    /// Discover all JSONL session files.
    private func discoverSessionFiles() throws -> [SessionFileInfo] {
        var files: [SessionFileInfo] = []

        guard FileManager.default.fileExists(atPath: claudeProjectsPath.path) else {
            return files
        }

        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]

        guard let enumerator = fileManager.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            // Skip subagents directories
            if fileURL.pathComponents.contains("subagents") {
                if fileURL.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Only process JSONL files
            guard fileURL.pathExtension == "jsonl" else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues?.isDirectory == false else { continue }

            let mtime = resourceValues?.contentModificationDate ?? Date()
            let size = Int64(resourceValues?.fileSize ?? 0)

            // Extract project path from URL
            // e.g., ~/.claude/projects/-Users-anthony-foo/session.jsonl
            //       -> projectPath = "-Users-anthony-foo"
            let relativePath = fileURL.path.replacingOccurrences(of: claudeProjectsPath.path + "/", with: "")
            let components = relativePath.split(separator: "/")
            let projectPath = components.first.map(String.init) ?? ""

            files.append(SessionFileInfo(
                url: fileURL,
                path: fileURL.path,
                projectPath: projectPath,
                mtime: mtime,
                size: size
            ))
        }

        return files
    }
}

/// Information about a discovered session file.
private struct SessionFileInfo {
    let url: URL
    let path: String
    let projectPath: String
    let mtime: Date
    let size: Int64
}
