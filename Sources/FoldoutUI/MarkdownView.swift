import FoldoutCore
import SwiftUI

struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { block in
                    BlockView(block: block)
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.kind {
        case .heading(let level):
            VStack(alignment: .leading, spacing: 6) {
                Text(block.text).font(headingFont(level)).padding(.top, level <= 2 ? 8 : 4)
                if level <= 2 { Divider() }
            }
        case .paragraph:
            Text(block.text).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                Text(block.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth - 1) * 18)
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text).font(.system(.callout, design: .monospaced)).padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        case .quote:
            Text(block.text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3) }
        case .rule:
            Divider().padding(.vertical, 4)
        case .tableRow(let header):
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(block.cells.enumerated()), id: \.offset) { _, cell in
                    Text(cell)
                        .fontWeight(header ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                }
            }
            .background(header ? Color.primary.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) { Divider() }
            .padding(.vertical, -5)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 26, weight: .bold)
        case 2: .system(size: 21, weight: .semibold)
        case 3: .system(size: 17, weight: .semibold)
        default: .system(size: 14, weight: .semibold)
        }
    }
}
