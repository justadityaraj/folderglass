import Foundation

public struct MarkdownBlock: Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(Int)
        case paragraph
        case listItem(marker: String, depth: Int)
        case code(language: String?)
        case quote
        case rule
        case tableRow(header: Bool)
    }

    public let id: Int
    public let kind: Kind
    public var cells: [AttributedString]

    public var text: AttributedString { cells.first ?? AttributedString() }
    public var plainText: String { String(text.characters) }
}

public enum MarkdownDocument {
    public static func blocks(from source: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let document = try? AttributedString(markdown: stripHTML(source), options: options) else {
            return [MarkdownBlock(id: 0, kind: .paragraph, cells: [AttributedString(source)])]
        }

        var blocks: [MarkdownBlock] = []
        var lastIntent: PresentationIntent?
        var lastRow: Int?

        for (intent, range) in document.runs[\.presentationIntent] {
            var piece = AttributedString(document[range])
            piece.presentationIntent = nil
            if intent == lastIntent, !blocks.isEmpty {
                let index = blocks.count - 1
                blocks[index].cells[blocks[index].cells.count - 1].append(piece)
                continue
            }
            lastIntent = intent
            let components = intent?.components ?? []
            let kind = kind(for: components)

            if case .tableRow = kind {
                let row = rowIdentity(components)
                if row == lastRow, !blocks.isEmpty {
                    blocks[blocks.count - 1].cells.append(piece)
                    continue
                }
                lastRow = row
            } else {
                lastRow = nil
            }
            if case .rule = kind { piece = AttributedString() }
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, cells: [piece]))
        }

        return blocks.map { block in
            var trimmed = block
            trimmed.cells = block.cells.map(trimTrailingNewlines)
            return trimmed
        }
    }

    static func kind(for components: [PresentationIntent.IntentType]) -> MarkdownBlock.Kind {
        var lists: [(ordered: Bool, ordinal: Int)] = []
        var ordinal = 1
        var isListItem = false
        for component in components {
            switch component.kind {
            case .codeBlock(let language): return .code(language: language)
            case .header(let level): return .heading(level)
            case .thematicBreak: return .rule
            case .tableHeaderRow: return .tableRow(header: true)
            case .tableRow: return .tableRow(header: false)
            case .listItem(let number): if !isListItem { ordinal = number; isListItem = true }
            case .orderedList: lists.append((true, ordinal))
            case .unorderedList: lists.append((false, ordinal))
            default: break
            }
        }
        if isListItem, let nearest = lists.first {
            return .listItem(marker: nearest.ordered ? "\(nearest.ordinal)." : "•", depth: lists.count)
        }
        if components.contains(where: { $0.kind == .blockQuote }) { return .quote }
        return .paragraph
    }

    static func rowIdentity(_ components: [PresentationIntent.IntentType]) -> Int? {
        for component in components {
            switch component.kind {
            case .tableHeaderRow: return -component.identity
            case .tableRow: return component.identity
            default: continue
            }
        }
        return nil
    }

    static func stripHTML(_ source: String) -> String {
        var inFence = false
        return source.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            guard !inFence else { return line }
            let cleaned = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if cleaned.trimmingCharacters(in: .whitespaces).isEmpty && !trimmed.isEmpty { return nil }
            return cleaned
        }.joined(separator: "\n")
    }

    static func trimTrailingNewlines(_ text: AttributedString) -> AttributedString {
        var result = text
        while let last = result.characters.last, last.isNewline {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex)
        }
        return result
    }
}
