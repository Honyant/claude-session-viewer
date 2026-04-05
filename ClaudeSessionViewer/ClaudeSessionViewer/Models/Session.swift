import Foundation
import GRDB

/// Represents a Claude Code session transcript
struct Session: Identifiable, Codable, Hashable {
    var id: String  // UUID from session
    var slug: String?
    var projectPath: String
    var cwd: String?
    var startTime: Date
    var lastUpdated: Date
    var messageCount: Int
    var filePath: String
    var fileMtime: Date
    var fileSize: Int64

    var displayName: String {
        if let slug = slug, !slug.isEmpty {
            return slug
        }
        return String(id.prefix(8))
    }

    var projectDisplayName: String {
        // Convert hyphenated path back to readable form
        // e.g., "-Users-anthony-Projects-foo" -> "foo"
        let parts = projectPath.split(separator: "-").map(String.init)
        return parts.last ?? projectPath
    }
}

// MARK: - GRDB TableRecord
extension Session: TableRecord, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sessions"

    enum Columns: String, ColumnExpression {
        case id, slug, projectPath, cwd, startTime, lastUpdated
        case messageCount, filePath, fileMtime, fileSize
    }
}

// MARK: - Database Schema
extension Session {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column(Columns.id.rawValue, .text).primaryKey()
            t.column(Columns.slug.rawValue, .text)
            t.column(Columns.projectPath.rawValue, .text).notNull().indexed()
            t.column(Columns.cwd.rawValue, .text)
            t.column(Columns.startTime.rawValue, .datetime).notNull()
            t.column(Columns.lastUpdated.rawValue, .datetime).notNull()
            t.column(Columns.messageCount.rawValue, .integer).notNull()
            t.column(Columns.filePath.rawValue, .text).notNull().unique()
            t.column(Columns.fileMtime.rawValue, .datetime).notNull()
            t.column(Columns.fileSize.rawValue, .integer).notNull()
        }
    }
}
