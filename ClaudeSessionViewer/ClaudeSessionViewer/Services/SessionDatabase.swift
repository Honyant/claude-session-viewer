import Foundation
import GRDB

/// Manages SQLite database for session indexing and full-text search.
///
/// Optimizations:
/// - Enables WAL mode (faster writes + better read/write concurrency).
/// - Uses batched inserts for messages.
/// - Exposes a lightweight file index to avoid per-file DB lookups during scanning.
actor SessionDatabase {
    private var dbPool: DatabasePool?

    private var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeSessionViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("sessions.sqlite")
    }

    /// Initialize the database, creating tables if needed.
    func initialize() async throws {
        var config = Configuration()

        config.prepareDatabase { db in
            // SQLite performance and correctness settings.
            // WAL improves performance for frequent incremental indexing.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // NORMAL is a good balance for a local cache/index.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            // Ensure cascade deletes work as expected.
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            #if DEBUG
            db.trace { print("SQL: \($0)") }
            #endif
        }

        dbPool = try DatabasePool(path: databaseURL.path, configuration: config)

        try await dbPool?.write { db in
            try Session.createTable(in: db)
            try Message.createTable(in: db)
        }
    }

    /// A lightweight index of file metadata for all sessions.
    ///
    /// Keyed by `filePath` so the scanner can decide which files need reindexing
    /// without doing one query per file.
    func fetchSessionFileIndex() async throws -> [String: (id: String, mtime: Date, size: Int64)] {
        guard let dbPool else { return [:] }

        struct RowInfo: FetchableRecord, Decodable {
            var id: String
            var filePath: String
            var fileMtime: Date
            var fileSize: Int64
        }

        return try await dbPool.read { db in
            let rows = try RowInfo.fetchAll(db, sql: "SELECT id, filePath, fileMtime, fileSize FROM sessions")
            var index: [String: (id: String, mtime: Date, size: Int64)] = [:]
            index.reserveCapacity(rows.count)
            for row in rows {
                index[row.filePath] = (id: row.id, mtime: row.fileMtime, size: row.fileSize)
            }
            return index
        }
    }

    /// Check if a session file needs reindexing based on mtime and size.
    func needsReindex(filePath: String, mtime: Date, size: Int64) async throws -> Bool {
        guard let dbPool else { return true }

        return try await dbPool.read { db in
            if let existing = try Session
                .filter(Session.Columns.filePath == filePath)
                .fetchOne(db) {
                // Reindex if file has been modified.
                return existing.fileMtime != mtime || existing.fileSize != size
            }
            return true
        }
    }

    /// Save a session and its messages to the database.
    ///
    /// We delete by `filePath` (unique) to handle rare cases where the parsed session id changes
    /// (for example, older files without a `sessionId` later gaining one).
    func save(session: Session, messages: [Message]) async throws {
        guard let dbPool else { return }

        try await dbPool.write { db in
            // Remove any previous version of this session (cascades messages).
            _ = try Session
                .filter(Session.Columns.filePath == session.filePath)
                .deleteAll(db)

            // Insert new session.
            try session.insert(db)

            // Insert messages (GRDB caches prepared statements internally).
            for message in messages {
                try message.insert(db)
            }
        }
    }

    /// Fetch all sessions (excluding empty ones).
    func fetchAllSessions() async throws -> [Session] {
        guard let dbPool else { return [] }

        return try await dbPool.read { db in
            try Session
                .filter(Session.Columns.messageCount > 0)
                .order(Session.Columns.lastUpdated.desc)
                .fetchAll(db)
        }
    }

    /// Fetch messages for a specific session.
    func fetchMessages(forSession sessionId: String) async throws -> [Message] {
        guard let dbPool else { return [] }

        return try await dbPool.read { db in
            try Message
                .filter(Message.Columns.sessionId == sessionId)
                .order(Message.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    /// Search messages using full-text search with recency ranking.
    func searchMessages(query: String) async throws -> [(Message, Session?)] {
        guard let dbPool, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try await dbPool.read { db in
            // Build FTS5 query - escape special characters and add prefix matching.
            let sanitizedQuery = query
                .replacingOccurrences(of: "\"", with: "\"\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let ftsQuery = sanitizedQuery
                .split(separator: " ")
                .map { "\"\($0)\"*" }
                .joined(separator: " ")

            // Query messages with recency-weighted ranking.
            //
            // Note: SQLite's FTS5 `bm25()` returns smaller values for better matches. We multiply it by a
            // recency factor so newer messages get a small boost.
            let sql = """
                SELECT messages.*
                FROM messages_fts
                JOIN messages ON messages.rowid = messages_fts.rowid
                WHERE messages_fts MATCH ?
                ORDER BY bm25(messages_fts) / (1.0 + 1.0 / (julianday('now') - julianday(messages.timestamp) + 1))
                LIMIT 100
                """

            let messages = try Message.fetchAll(db, sql: sql, arguments: [ftsQuery])

            // Batch fetch all sessions in a single query.
            let sessionIds = Set(messages.map(\.sessionId))
            let sessions = try Session
                .filter(sessionIds.contains(Session.Columns.id))
                .fetchAll(db)
            let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

            return messages.map { message in
                (message, sessionMap[message.sessionId])
            }
        }
    }

    /// Run ANALYZE to optimize query planner after bulk indexing.
    func runAnalyze() async throws {
        guard let dbPool else { return }

        try await dbPool.write { db in
            try db.execute(sql: "ANALYZE")
        }
    }

    /// Delete sessions whose files no longer exist.
    ///
    /// Returns `true` if anything was deleted.
    func cleanupOrphanedSessions(existingPaths: Set<String>) async throws -> Bool {
        guard let dbPool else { return false }

        struct RowInfo: FetchableRecord, Decodable {
            var id: String
            var filePath: String
        }

        return try await dbPool.write { db in
            let rows = try RowInfo.fetchAll(db, sql: "SELECT id, filePath FROM sessions")
            var deletedAny = false

            for row in rows where !existingPaths.contains(row.filePath) {
                try Session.deleteOne(db, key: row.id)
                deletedAny = true
            }

            return deletedAny
        }
    }

    /// Delete sessions by their IDs.
    func deleteSessions(ids: [String]) async throws {
        guard let dbPool, !ids.isEmpty else { return }

        try await dbPool.write { db in
            for id in ids {
                try Session.deleteOne(db, key: id)
            }
        }
    }

    /// Get database statistics.
    func getStats() async throws -> (sessionCount: Int, messageCount: Int) {
        guard let dbPool else { return (0, 0) }

        return try await dbPool.read { db in
            let sessions = try Session.fetchCount(db)
            let messages = try Message.fetchCount(db)
            return (sessions, messages)
        }
    }
}
