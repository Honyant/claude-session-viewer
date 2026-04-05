import Foundation
import GRDB

/// Represents a single message in a Claude Code session
struct Message: Identifiable, Codable, Hashable {
    var id: String  // UUID from message
    var sessionId: String
    var role: MessageRole
    var contentText: String
    var timestamp: Date
    var parentUuid: String?
    var toolUse: [ToolUseInfo]?
    var isToolResult: Bool

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }

    init(id: String, sessionId: String, role: MessageRole, contentText: String, timestamp: Date, parentUuid: String?, toolUse: [ToolUseInfo]?, isToolResult: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.contentText = contentText
        self.timestamp = timestamp
        self.parentUuid = parentUuid
        self.toolUse = toolUse
        self.isToolResult = isToolResult
    }
}

/// Tool use information extracted from assistant messages
struct ToolUseInfo: Codable, Hashable {
    var name: String
    var input: String?  // JSON string of input parameters
}

// MARK: - GRDB TableRecord
extension Message: TableRecord, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    enum Columns: String, ColumnExpression {
        case id, sessionId, role, contentText, timestamp, parentUuid, toolUse, isToolResult
    }
}

// MARK: - Database Schema
extension Message {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column(Columns.id.rawValue, .text).primaryKey()
            t.column(Columns.sessionId.rawValue, .text)
                .notNull()
                .indexed()
                .references(Session.databaseTableName, onDelete: .cascade)
            t.column(Columns.role.rawValue, .text).notNull()
            t.column(Columns.contentText.rawValue, .text).notNull()
            t.column(Columns.timestamp.rawValue, .datetime).notNull().indexed()
            t.column(Columns.parentUuid.rawValue, .text)
            t.column(Columns.toolUse.rawValue, .text)  // JSON encoded
            t.column(Columns.isToolResult.rawValue, .boolean).notNull().defaults(to: false)
        }

        // Create FTS5 virtual table for full-text search (if not exists)
        if try !db.tableExists("messages_fts") {
            try db.create(virtualTable: "messages_fts", using: FTS5()) { t in
                t.synchronize(withTable: databaseTableName)
                t.tokenizer = .porter()
                t.column(Columns.contentText.rawValue)
            }
        }
    }
}

// MARK: - FTS Search
extension Message {
    /// Search messages using full-text search
    static func search(_ query: String, in db: Database) throws -> [Message] {
        let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
        let sql = """
            SELECT messages.*
            FROM messages
            JOIN messages_fts ON messages.id = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY messages.timestamp DESC
            LIMIT 100
            """
        return try Message.fetchAll(db, sql: sql, arguments: [pattern])
    }
}
