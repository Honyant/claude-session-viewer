import SwiftUI

struct MessageBubble: View {
    let message: Message
    var highlightText: String = ""

    var body: some View {
        if message.isToolResult {
            ToolResultBubble(message: message)
        } else {
            RegularMessageBubble(message: message, highlightText: highlightText)
        }
    }
}

// MARK: - Tool Result Bubble (Collapsible)
struct ToolResultBubble: View {
    let message: Message
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .frame(width: 24, height: 24)

                    Text("Tool Result")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.7))

                    Text(formattedTime)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Spacer()

                    Text(truncatedPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 300, alignment: .trailing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.green.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 12))

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(message.contentText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.8))
                        .textSelection(.enabled)
                        .padding(16)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 8)
                .padding(.leading, 34)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contextMenu {
            Button("Copy Tool Result") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.contentText, forType: .string)
            }
        }
    }

    private var formattedTime: String {
        DateFormatters.shortTime.string(from: message.timestamp)
    }

    private var truncatedPreview: String {
        let text = message.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        if firstLine.count > 50 {
            return String(firstLine.prefix(50)) + "..."
        }
        return firstLine
    }
}

// MARK: - Regular Message Bubble
struct RegularMessageBubble: View {
    let message: Message
    var highlightText: String = ""
    @State private var isHovered = false

    private var isUser: Bool {
        message.role == .user
    }

    private var roleIcon: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .assistant:
            return "sparkles"
        case .system:
            return "gear"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .purple
        case .system:
            return .red
        }
    }

    private var roleName: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Claude"
        case .system:
            return "System"
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.contentText, forType: .string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon + Name + Time + Copy Button
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.15))

                    Image(systemName: roleIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(roleColor)
                }
                .frame(width: 24, height: 24)

                Text(roleName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.9))

                Text(DateFormatters.shortTime.string(from: message.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))

                Spacer()

                // Copy button (visible on hover)
                Button(action: copyMessage) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy message")
                .opacity(isHovered ? 1 : 0)
            }

            // Content
            VStack(alignment: .leading, spacing: 12) {
                MessageContent(text: message.contentText, highlightText: highlightText)

                // Tool use info
                if let tools = message.toolUse, !tools.isEmpty {
                    ToolUseView(tools: tools)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUser ? Color.blue.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Copy Message") {
                copyMessage()
            }
        }
    }
}

// MARK: - Message Content with Selectable Markdown
struct MessageContent: View {
    let text: String
    var highlightText: String = ""

    @State private var baseAttributed: AttributedString = AttributedString("")
    @State private var renderedAttributed: AttributedString = AttributedString("")

    var body: some View {
        Text(renderedAttributed)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                let parsed = Self.parseMarkdown(text)
                baseAttributed = parsed
                renderedAttributed = Self.applyHighlight(to: parsed, searchText: highlightText)
            }
            .onChange(of: highlightText) { newValue in
                renderedAttributed = Self.applyHighlight(to: baseAttributed, searchText: newValue)
            }
    }

    private static func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }

    private static func applyHighlight(to base: AttributedString, searchText: String) -> AttributedString {
        guard !searchText.isEmpty else { return base }

        var result = base
        let needle = searchText.lowercased()
        let haystack = String(result.characters).lowercased()
        var searchStart = haystack.startIndex

        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let startOffset = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let start = result.index(result.startIndex, offsetByCharacters: startOffset)
            let end = result.index(start, offsetByCharacters: needle.count)
            result[start..<end].backgroundColor = .yellow.opacity(0.4)
            searchStart = range.upperBound
        }

        return result
    }
}

// MARK: - Simple Markdown Parser
enum MarkdownParser {
    /// Parse markdown to SwiftUI AttributedString
    static func parseToAttributedString(_ text: String, highlightText: String = "") -> AttributedString {
        // Use SwiftUI's built-in markdown parsing as base
        var result: AttributedString
        do {
            result = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            result = AttributedString(text)
        }

        // Apply search highlighting if needed
        if !highlightText.isEmpty {
            let searchText = highlightText.lowercased()
            var currentIndex = result.startIndex

            while currentIndex < result.endIndex {
                let remainingRange = currentIndex..<result.endIndex
                let searchString = String(result[remainingRange].characters).lowercased()

                if let foundRange = searchString.range(of: searchText) {
                    let distance = searchString.distance(from: searchString.startIndex, to: foundRange.lowerBound)
                    let length = searchText.count

                    let attrStart = result.index(currentIndex, offsetByCharacters: distance)
                    let attrEnd = result.index(attrStart, offsetByCharacters: length)

                    result[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.4)
                    currentIndex = attrEnd
                } else {
                    break
                }
            }
        }

        return result
    }

    static func parse(_ text: String, highlightText: String = "") -> NSAttributedString {
        let result = NSMutableAttributedString()

        let baseFont = NSFont.systemFont(ofSize: 14)
        let boldFont = NSFont.boldSystemFont(ofSize: 14)
        let italicFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic), size: 14) ?? baseFont
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let headingFont1 = NSFont.boldSystemFont(ofSize: 20)
        let headingFont2 = NSFont.boldSystemFont(ofSize: 18)
        let headingFont3 = NSFont.boldSystemFont(ofSize: 16)

        let textColor = NSColor.labelColor
        let codeBackground = NSColor.textBackgroundColor.withAlphaComponent(0.8)
        let codeBlockBackground = NSColor.windowBackgroundColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        for line in lines {
            // Handle code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    let codeBlockStyle = NSMutableParagraphStyle()
                    codeBlockStyle.lineSpacing = 2

                    let codeAttrs: [NSAttributedString.Key: Any] = [
                        .font: codeFont,
                        .foregroundColor: textColor.withAlphaComponent(0.9),
                        .backgroundColor: codeBlockBackground,
                        .paragraphStyle: codeBlockStyle
                    ]

                    if !codeBlockContent.isEmpty {
                        // Add newline before code block if needed
                        if result.length > 0 {
                            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                        }
                        result.append(NSAttributedString(string: codeBlockContent, attributes: codeAttrs))
                        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                    }
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    // Start code block
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty {
                    codeBlockContent += "\n"
                }
                codeBlockContent += line
                continue
            }

            var processedLine = line
            var lineAttributes = baseAttributes

            // Handle headings
            if line.hasPrefix("### ") {
                processedLine = String(line.dropFirst(4))
                lineAttributes[.font] = headingFont3
            } else if line.hasPrefix("## ") {
                processedLine = String(line.dropFirst(3))
                lineAttributes[.font] = headingFont2
            } else if line.hasPrefix("# ") {
                processedLine = String(line.dropFirst(2))
                lineAttributes[.font] = headingFont1
            }

            // Handle list items
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                processedLine = "•  " + String(line.dropFirst(2))
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                processedLine = String(line[match]) + String(line[match.upperBound...])
            }

            // Process inline formatting
            let attributedLine = parseInlineFormatting(
                processedLine,
                baseAttributes: lineAttributes,
                boldFont: boldFont,
                italicFont: italicFont,
                codeFont: codeFont,
                codeBackground: codeBackground
            )

            if result.length > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            result.append(attributedLine)
        }

        // Apply search highlighting if needed
        if !highlightText.isEmpty {
            let searchText = highlightText.lowercased()
            let fullText = result.string.lowercased()
            var searchRange = fullText.startIndex

            while let range = fullText.range(of: searchText, range: searchRange..<fullText.endIndex) {
                let nsRange = NSRange(range, in: fullText)
                result.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.4), range: nsRange)
                searchRange = range.upperBound
            }
        }

        return result
    }

    private static func parseInlineFormatting(
        _ text: String,
        baseAttributes: [NSAttributedString.Key: Any],
        boldFont: NSFont,
        italicFont: NSFont,
        codeFont: NSFont,
        codeBackground: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Process inline code first (to avoid conflicts with bold/italic)
        let codePattern = #"`([^`]+)`"#
        processPattern(codePattern, in: result) { range, match in
            let codeText = String(match.dropFirst().dropLast())
            let replacement = NSAttributedString(string: codeText, attributes: [
                .font: codeFont,
                .foregroundColor: baseAttributes[.foregroundColor] as Any,
                .backgroundColor: codeBackground,
                .paragraphStyle: baseAttributes[.paragraphStyle] as Any
            ])
            result.replaceCharacters(in: range, with: replacement)
        }

        // Process bold (**text** or __text__)
        let boldPattern = #"\*\*([^*]+)\*\*|__([^_]+)__"#
        processPattern(boldPattern, in: result) { range, match in
            var innerText = match
            if innerText.hasPrefix("**") {
                innerText = String(innerText.dropFirst(2).dropLast(2))
            } else {
                innerText = String(innerText.dropFirst(2).dropLast(2))
            }
            var attrs = baseAttributes
            attrs[.font] = boldFont
            result.replaceCharacters(in: range, with: NSAttributedString(string: innerText, attributes: attrs))
        }

        // Process italic (*text* or _text_) - be careful not to match ** or __
        let italicPattern = #"(?<!\*)\*([^*]+)\*(?!\*)|(?<!_)_([^_]+)_(?!_)"#
        processPattern(italicPattern, in: result) { range, match in
            let innerText = String(match.dropFirst().dropLast())
            var attrs = baseAttributes
            attrs[.font] = italicFont
            result.replaceCharacters(in: range, with: NSAttributedString(string: innerText, attributes: attrs))
        }

        // Process links [text](url)
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            var offset = 0
            let matches = regex.matches(in: result.string, range: NSRange(location: 0, length: result.length))
            for match in matches {
                let adjustedRange = NSRange(location: match.range.location - offset, length: match.range.length)
                if let textRange = Range(match.range(at: 1), in: result.string),
                   let urlRange = Range(match.range(at: 2), in: result.string) {
                    let linkText = String(result.string[textRange])
                    let urlString = String(result.string[urlRange])

                    var attrs = baseAttributes
                    attrs[.foregroundColor] = NSColor.linkColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let url = URL(string: urlString) {
                        attrs[.link] = url
                    }

                    let replacement = NSAttributedString(string: linkText, attributes: attrs)
                    result.replaceCharacters(in: adjustedRange, with: replacement)
                    offset += match.range.length - linkText.count
                }
            }
        }

        return result
    }

    private static func processPattern(_ pattern: String, in attributedString: NSMutableAttributedString, handler: (NSRange, String) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))

        // Process from end to beginning to avoid offset issues
        for match in matches.reversed() {
            let matchString = (attributedString.string as NSString).substring(with: match.range)
            handler(match.range, matchString)
        }
    }
}

// MARK: - Tool Use View
struct ToolUseView: View {
    let tools: [ToolUseInfo]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10))

                    Text("\(tools.count) tool call\(tools.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tools, id: \.name) { tool in
                        ToolUseRow(tool: tool)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.02))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct ToolUseRow: View {
    let tool: ToolUseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tool.name)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.7))

            if let input = tool.input {
                Text(input)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(message: Message(
            id: "1",
            sessionId: "session1",
            role: .user,
            contentText: "Hello, can you help me with a **coding** question?",
            timestamp: Date(),
            parentUuid: nil,
            toolUse: nil,
            isToolResult: false
        ), highlightText: "")

        MessageBubble(message: Message(
            id: "2",
            sessionId: "session1",
            role: .assistant,
            contentText: "Of course! Here's some code:\n\n```swift\nfunc hello() {\n    print(\"Hello, World!\")\n}\n```\n\nLet me know if you need help!",
            timestamp: Date(),
            parentUuid: "1",
            toolUse: [
                ToolUseInfo(name: "Read", input: "{\"path\": \"/Users/test/file.swift\"}")
            ],
            isToolResult: false
        ), highlightText: "")

        MessageBubble(message: Message(
            id: "3",
            sessionId: "session1",
            role: .user,
            contentText: "File contents here...\nLine 2\nLine 3",
            timestamp: Date(),
            parentUuid: "2",
            toolUse: nil,
            isToolResult: true
        ), highlightText: "")
    }
    .padding()
    .frame(width: 600)
}
