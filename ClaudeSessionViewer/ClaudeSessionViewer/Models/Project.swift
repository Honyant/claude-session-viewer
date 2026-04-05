import Foundation

/// Represents a project directory containing Claude Code sessions
struct Project: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var sessions: [Session]

    var displayName: String {
        // Use cwd from first session if available (preserves original folder name)
        if let cwd = sessions.first?.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        // Fallback: use the hyphenated path's last component
        let parts = path.split(separator: "-").map(String.init)
        if parts.count > 1 {
            return parts.last ?? path
        }
        return path
    }

    var fullPath: String {
        // Use cwd from first session if available
        if let cwd = sessions.first?.cwd {
            return cwd
        }
        // Fallback: convert hyphenated path back to actual path
        return path.replacingOccurrences(of: "-", with: "/")
    }

    var sessionCount: Int {
        sessions.count
    }

    var latestActivity: Date? {
        sessions.map(\.lastUpdated).max()
    }
}

extension Project {
    /// Group sessions by their project path
    static func groupSessions(_ sessions: [Session]) -> [Project] {
        let grouped = Dictionary(grouping: sessions, by: \.projectPath)
        return grouped.map { path, sessions in
            Project(
                path: path,
                sessions: sessions.sorted { $0.lastUpdated > $1.lastUpdated }
            )
        }
        .sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }
    }
}
