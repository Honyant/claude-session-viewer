import Foundation

/// Parses Claude Code session JSONL files.
///
/// Optimizations:
/// - Streams the file instead of loading it all at once (lower peak memory).
/// - Uses local date formatters per parse call to avoid thread-safety issues.
struct SessionParser: Sendable {

    /// Result of parsing a session file
    struct ParsedSession {
        var sessionId: String
        var slug: String?
        var cwd: String?
        var startTime: Date
        var lastUpdated: Date
        var messages: [Message]
    }

    /// Parse a JSONL file and extract session data
    func parse(fileAt url: URL) throws -> ParsedSession {
        // `DateFormatter` and `ISO8601DateFormatter` are not guaranteed to be thread-safe, so we keep them local.
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackDateFormatter = ISO8601DateFormatter()
        fallbackDateFormatter.formatOptions = [.withInternetDateTime]

        func parseDate(_ string: String) -> Date? {
            dateFormatter.date(from: string) ?? fallbackDateFormatter.date(from: string)
        }

        // Fallback session id from filename (used if the JSONL doesn't contain `sessionId`)
        let fallbackSessionId = url.deletingPathExtension().lastPathComponent
        var resolvedSessionId = fallbackSessionId

        var slug: String?
        var cwd: String?
        var startTime: Date?
        var lastUpdated: Date?
        var messages: [Message] = []

        // Process one JSONL line
        func processLineData(_ rawLineData: Data) {
            // Handle CRLF files by trimming trailing `\r`.
            var lineData = rawLineData
            if lineData.last == 0x0D {
                lineData.removeLast()
            }
            guard !lineData.isEmpty else { return }

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            // Extract session metadata from the earliest available event
            if let sid = json["sessionId"] as? String, sid != resolvedSessionId {
                resolvedSessionId = sid

                // If we already created messages before discovering `sessionId`,
                // update them so all messages consistently point at the same session.
                if !messages.isEmpty {
                    for i in messages.indices {
                        messages[i].sessionId = sid
                    }
                }
            }

            if slug == nil, let s = json["slug"] as? String {
                slug = s
            }

            if cwd == nil, let c = json["cwd"] as? String {
                cwd = c
            }

            // Track start/last timestamps
            if let timestampStr = json["timestamp"] as? String,
               let timestamp = parseDate(timestampStr) {
                if startTime == nil {
                    startTime = timestamp
                }
                lastUpdated = timestamp
            }

            // Parse message events
            guard let type = json["type"] as? String,
                  (type == "user" || type == "assistant"),
                  let uuid = json["uuid"] as? String,
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  let content = message["content"] else {
                return
            }

            let (contentText, isToolResult) = extractTextContent(from: content)
            let toolUse = extractToolUse(from: content)

            guard let timestampStr = json["timestamp"] as? String,
                  let timestamp = parseDate(timestampStr) else {
                return
            }

            let msg = Message(
                id: uuid,
                sessionId: resolvedSessionId,
                role: role == "user" ? .user : .assistant,
                contentText: contentText,
                timestamp: timestamp,
                parentUuid: json["parentUuid"] as? String,
                toolUse: toolUse.isEmpty ? nil : toolUse,
                isToolResult: isToolResult
            )
            messages.append(msg)
        }

        // Stream the file instead of loading it all at once.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let newline: UInt8 = 0x0A
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024)
            guard let chunk, !chunk.isEmpty else { break }

            buffer.append(chunk)

            // Consume complete lines from the buffer
            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = buffer.subdata(in: 0..<newlineIndex)
                buffer.removeSubrange(0...newlineIndex)
                if !lineData.isEmpty {
                    processLineData(lineData)
                }
            }
        }

        // Process trailing partial line (if the file doesn't end with a newline)
        if !buffer.isEmpty {
            processLineData(buffer)
        }

        return ParsedSession(
            sessionId: resolvedSessionId,
            slug: slug,
            cwd: cwd,
            startTime: startTime ?? Date(),
            lastUpdated: lastUpdated ?? Date(),
            messages: messages
        )
    }

    private func extractTextContent(from content: Any) -> (String, Bool) {
        if let text = content as? String {
            return (text, false)
        }

        guard let contentArray = content as? [[String: Any]] else {
            return ("", false)
        }

        var textParts: [String] = []
        textParts.reserveCapacity(contentArray.count)

        var hasToolResult = false
        var hasOnlyToolResult = true

        for item in contentArray {
            if let type = item["type"] as? String {
                switch type {
                case "text":
                    if let text = item["text"] as? String {
                        textParts.append(text)
                        hasOnlyToolResult = false
                    }
                case "tool_use":
                    if let name = item["name"] as? String {
                        textParts.append("[Tool: \(name)]")
                        hasOnlyToolResult = false
                    }
                case "tool_result":
                    hasToolResult = true
                    if let resultContent = item["content"] as? String {
                        textParts.append(resultContent)
                    } else if let resultArray = item["content"] as? [[String: Any]] {
                        // Handle array content in tool results
                        for resultItem in resultArray {
                            if let text = resultItem["text"] as? String {
                                textParts.append(text)
                            }
                        }
                    }
                default:
                    break
                }
            }
        }

        // Only mark as tool result if it contains tool_result and nothing else meaningful
        let isToolResult = hasToolResult && hasOnlyToolResult

        return (textParts.joined(separator: "\n"), isToolResult)
    }

    private func extractToolUse(from content: Any) -> [ToolUseInfo] {
        guard let contentArray = content as? [[String: Any]] else {
            return []
        }

        var tools: [ToolUseInfo] = []
        tools.reserveCapacity(contentArray.count)

        for item in contentArray {
            if let type = item["type"] as? String, type == "tool_use",
               let name = item["name"] as? String {
                var inputStr: String?
                if let input = item["input"] {
                    if let data = try? JSONSerialization.data(withJSONObject: input),
                       let str = String(data: data, encoding: .utf8) {
                        inputStr = str
                    }
                }
                tools.append(ToolUseInfo(name: name, input: inputStr))
            }
        }

        return tools
    }
}
