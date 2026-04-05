# Claude Session Viewer

A native macOS app to browse, search, and view Claude Code session transcripts.

## Features

- **Session Discovery**: Automatically scans `~/.claude/projects/` for session files
- **Full-Text Search**: Search across all conversations using SQLite FTS5
- **In-Session Search**: Filter and highlight text within a specific session
- **Live Updates**: Watches for new sessions and updates automatically
- **Project Grouping**: Sessions organized by project directory

## Requirements

- macOS 13.0+
- Swift 5.9+

## Building

```bash
cd ClaudeSessionViewer
swift build
```

## Running

```bash
swift run
```

Or after building:

```bash
.build/debug/ClaudeSessionViewer
```

## Usage

1. **Browse Sessions**: The sidebar shows all projects with their sessions, sorted by most recent activity
2. **Global Search**: Use the search bar in the sidebar to search across all sessions
3. **View Conversation**: Click a session to view its messages
4. **In-Session Search**: Use Cmd+F or the toolbar search to filter messages within the current session
5. **Refresh**: Press Cmd+R to rescan for new sessions

## Data Storage

- **Session Index**: `~/Library/Application Support/ClaudeSessionViewer/sessions.sqlite`
- **Source Files**: `~/.claude/projects/<project>/*.jsonl`

## Architecture

```
ClaudeSessionViewer/
├── Models/
│   ├── Session.swift      # Session metadata
│   ├── Message.swift      # Individual messages with FTS
│   └── Project.swift      # Project grouping
├── Services/
│   ├── SessionScanner.swift   # File discovery & watching
│   ├── SessionParser.swift    # JSONL parsing
│   └── SessionDatabase.swift  # SQLite + FTS5
├── ViewModels/
│   └── SessionViewModel.swift # State management
└── Views/
    ├── ContentView.swift      # Main layout
    ├── SidebarView.swift      # Project/session list
    ├── ConversationView.swift # Message display
    └── MessageBubble.swift    # Message styling
```

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite wrapper with FTS5 support
