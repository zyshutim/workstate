import SwiftUI

enum WorkstateMarkdownStyle: Equatable {
    case message
    case reportLead
    case report

    var bodyFont: Font {
        switch self {
        case .message: WorkstateTheme.bodyFont
        case .reportLead: WorkstateReportTokens.leadBodyFont
        case .report: WorkstateReportTokens.bodyFont
        }
    }

    var blockSpacing: CGFloat {
        switch self {
        case .message: 7
        case .reportLead, .report: WorkstateReportTokens.blockSpacing
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .message: 2
        case .reportLead, .report: WorkstateReportTokens.bodyLineSpacing
        }
    }

    func headingFont(level: Int) -> Font {
        switch self {
        case .message:
            level == 1 ? WorkstateTheme.sectionTitleFont : WorkstateTheme.headlineFont
        case .reportLead:
            level == 1
                ? WorkstateReportTokens.leadTitleFont
                : WorkstateReportTokens.subsectionTitleFont
        case .report:
            level == 1
                ? WorkstateReportTokens.sectionTitleFont
                : WorkstateReportTokens.subsectionTitleFont
        }
    }
}

struct WorkstateMarkdownView: View {
    let source: String
    var style: WorkstateMarkdownStyle = .message

    private var blocks: [WorkstateMarkdownBlock] {
        WorkstateMarkdownParser.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: WorkstateMarkdownBlock) -> some View {
        switch block {
        case let .paragraph(text):
            markdownText(text)
                .font(style.bodyFont)

        case let .heading(level, text):
            markdownText(text)
                .font(style.headingFont(level: level))
                .padding(.top, level == 1 ? 3 : 1)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(WorkstateTheme.secondaryLabel)
                    .frame(width: 5, height: 5)
                markdownText(text)
                    .font(style.bodyFont)
            }
            .padding(.leading, style == .message ? 0 : WorkstateReportTokens.listIndent)

        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(number).")
                    .font(WorkstateReportTokens.metadataFont.monospacedDigit())
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
                    .frame(minWidth: 18, alignment: .trailing)
                markdownText(text)
                    .font(style.bodyFont)
            }
            .padding(.leading, style == .message ? 0 : WorkstateReportTokens.listIndent - 6)

        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(WorkstateTheme.secondaryLabel.opacity(0.52))
                    .frame(width: 2)
                markdownText(text)
                    .font(style.bodyFont)
                    .foregroundStyle(WorkstateTheme.secondaryLabel)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .code(text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(9)
            }
            .background(
                WorkstateTheme.primaryLabel.opacity(0.07),
                in: RoundedRectangle(cornerRadius: WorkstateTheme.smallCornerRadius)
            )

        case .divider:
            Rectangle()
                .fill(WorkstateTheme.separator.opacity(0.58))
                .frame(height: 0.5)
                .padding(.vertical, 3)
        }
    }

    private func markdownText(_ text: String) -> some View {
        Text(inlineMarkdown(text))
            .lineSpacing(style.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private enum WorkstateMarkdownBlock {
    case paragraph(String)
    case heading(Int, String)
    case bullet(String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    case divider
}

private enum WorkstateMarkdownParser {
    static func parse(_ source: String) -> [WorkstateMarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [WorkstateMarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInsideCodeBlock {
                    flushCode()
                    isInsideCodeBlock = false
                } else {
                    flushParagraph()
                    isInsideCodeBlock = true
                }
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if line == "---" || line == "***" {
                flushParagraph()
                blocks.append(.divider)
            } else if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(.heading(heading.level, heading.text))
            } else if let bullet = bullet(from: line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
            } else if let numbered = numbered(from: line) {
                flushParagraph()
                blocks.append(.numbered(numbered.number, numbered.text))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2))))
            } else {
                paragraph.append(rawLine)
            }
        }

        if isInsideCodeBlock {
            flushCode()
        }
        flushParagraph()
        return blocks.isEmpty ? [.paragraph(source)] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...3).contains(level) else { return nil }
        let text = line.dropFirst(level)
        guard text.first?.isWhitespace == true else { return nil }
        return (level, String(text).trimmingCharacters(in: .whitespaces))
    }

    private static func bullet(from line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(from line: String) -> (number: String, text: String)? {
        guard let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let number = String(line[..<separator])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let remainder = line[line.index(after: separator)...]
        guard remainder.first?.isWhitespace == true else { return nil }
        return (number, String(remainder).trimmingCharacters(in: .whitespaces))
    }
}
