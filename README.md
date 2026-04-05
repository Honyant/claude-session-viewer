# Claude Session Viewer

A native macOS app to browse, search, and view your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) session transcripts.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Session Discovery** -- Automatically scans `~/.claude/projects/` for session files
- **Full-Text Search** -- Search across all conversations using SQLite FTS5
- **In-Session Search** -- Filter and highlight text within a specific session
- **Live Updates** -- Watches for new sessions and updates automatically
- **Project Grouping** -- Sessions organized by project directory

## Install

### DMG (recommended)

Download the latest `.dmg` from [Releases](https://github.com/Honyant/claude-session-viewer/releases), open it, and drag **Claude Session Viewer** into your Applications folder.

### Build from source

Requires macOS 13+ and Swift 5.9+.

```bash
cd ClaudeSessionViewer
swift build -c release
./build-app.sh
cp -r "Claude Session Viewer.app" /Applications/
```

### Create a DMG for distribution

```bash
cd ClaudeSessionViewer
./build-dmg.sh
```

This produces `Claude Session Viewer.dmg` ready to share.

## Usage

1. **Browse Sessions** -- The sidebar shows all projects with their sessions, sorted by most recent activity
2. **Global Search** -- Use the search bar in the sidebar to search across all sessions
3. **View Conversation** -- Click a session to view its messages
4. **In-Session Search** -- Use `Cmd+F` or the toolbar search to filter messages within the current session
5. **Refresh** -- Press `Cmd+R` to rescan for new sessions

## Architecture

```
ClaudeSessionViewer/
├── ClaudeSessionViewer/
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── Message.swift
│   │   └── Project.swift
│   ├── Services/
│   │   ├── SessionScanner.swift
│   │   ├── SessionParser.swift
│   │   └── SessionDatabase.swift
│   ├── ViewModels/
│   │   └── SessionViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── SidebarView.swift
│   │   ├── ConversationView.swift
│   │   ├── SearchView.swift
│   │   └── MessageBubble.swift
│   ├── Utilities/
│   │   └── DateFormatters.swift
│   └── Resources/
│       ├── Info.plist
│       └── AppIcon.icns
├── Package.swift
├── build-app.sh
└── build-dmg.sh
```

## Data Storage

| What | Where |
|------|-------|
| Session index | `~/Library/Application Support/ClaudeSessionViewer/sessions.sqlite` |
| Source files | `~/.claude/projects/<project>/*.jsonl` |

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) -- SQLite wrapper with FTS5 support
