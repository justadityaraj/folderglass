import AppKit
import FoldoutCore
import SwiftUI
import UniformTypeIdentifiers

public struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @State private var tab: Tab?

    enum Tab: String, CaseIterable, Identifiable {
        case contents = "Contents", largest = "Largest", recent = "Recent", readme = "README", images = "Images"
        var id: String { rawValue }
    }

    public init(model: PreviewModel, tab: String? = nil) {
        self.model = model
        _tab = State(initialValue: tab.flatMap(Tab.init(rawValue:)))
    }

    public var body: some View {
        Group {
            if model.content == .markdown {
                MarkdownView(blocks: model.readme)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let summary = model.summary, !summary.kinds.isEmpty { TypeBreakdown(kinds: summary.kinds) }
                    if let git = model.git { GitCard(git: git) }
                    tabs
                }
                .padding(18)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var availableTabs: [Tab] {
        var tabs: [Tab] = [.contents, .largest, .recent]
        if !model.readme.isEmpty { tabs.append(.readme) }
        if model.content == .folder, (model.summary?.imageCount ?? 0) > 0 { tabs.append(.images) }
        return tabs
    }

    private var defaultTab: Tab {
        if model.content == .folder, model.summary?.isMostlyImages == true { return .images }
        if model.git != nil, !model.readme.isEmpty { return .readme }
        return .contents
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: model.icon)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let summary = model.summary, !summary.isComplete, !summary.hitLimit {
                ProgressView().controlSize(.small)
            } else if model.summary == nil, !model.failed {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        guard let summary = model.summary else { return model.failed ? "Couldn't read this archive" : "Scanning…" }
        var parts = [Format.count(summary.fileCount, "file")]
        if summary.folderCount > 0 { parts.append(Format.count(summary.folderCount, "folder")) }
        parts.append(Format.bytes(summary.totalSize))
        if let latest = summary.latestModified { parts.append("updated \(Format.relative(latest))") }
        if summary.hitLimit { parts.append("stopped early, folder is huge") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var tabs: some View {
        let selected = tab.flatMap { availableTabs.contains($0) ? $0 : nil } ?? defaultTab
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Binding(get: { selected }, set: { tab = $0 })) {
                ForEach(availableTabs) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                switch selected {
                case .contents:
                    VStack(alignment: .leading, spacing: 6) {
                        FileTable(items: model.summary?.children ?? [], showsFolder: false, initialSort: .size)
                        if let summary = model.summary, summary.childCount > summary.children.count {
                            Text("Showing the \(summary.children.count) largest of \(summary.childCount.formatted()) items").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .largest: FileTable(items: model.summary?.largest ?? [], showsFolder: true, initialSort: .size)
                case .recent: FileTable(items: model.summary?.recent ?? [], showsFolder: true, initialSort: .modified)
                case .readme: MarkdownView(blocks: model.readme).clipShape(RoundedRectangle(cornerRadius: 8))
                case .images: ImageGrid(root: model.url, items: model.summary?.images ?? [], total: model.summary?.imageCount ?? 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TypeBreakdown: View {
    let kinds: [KindTotal]

    var body: some View {
        let total = max(1, kinds.reduce(Int64(0)) { $0 + $1.size })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(kinds, id: \.kind) { kind in
                        Rectangle()
                            .fill(Format.color(kind.kind))
                            .frame(width: max(3, geometry.size.width * CGFloat(kind.size) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack(spacing: 14) {
                ForEach(kinds.prefix(6), id: \.kind) { kind in
                    HStack(spacing: 5) {
                        Circle().fill(Format.color(kind.kind)).frame(width: 8, height: 8)
                        Text(kind.kind.title).font(.caption.weight(.medium))
                        Text("\(Format.bytes(kind.size)) · \(kind.count.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
            }
        }
    }
}

struct GitCard: View {
    let git: GitInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(git.branch ?? "detached at \(git.head?.prefix(7) ?? "?")").font(.callout.weight(.semibold))
                    if let status = git.status {
                        Text(Format.gitStatus(status))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(status.isClean ? Color.green.opacity(0.18) : Color.orange.opacity(0.2)))
                    }
                    if let remote = git.remote {
                        Text(remote).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                if let commit = git.lastCommit {
                    Text(commit.subject).font(.callout).lineLimit(1)
                    Text([String(commit.hash.prefix(7)), commit.author, commit.date.map(Format.relative)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

struct FileTable: View {
    enum SortKey { case name, size, modified }

    let items: [FileItem]
    let showsFolder: Bool
    @State private var order: [KeyPathComparator<FileItem>]

    init(items: [FileItem], showsFolder: Bool, initialSort: SortKey) {
        self.items = items
        self.showsFolder = showsFolder
        switch initialSort {
        case .name: _order = State(initialValue: [KeyPathComparator(\FileItem.name)])
        case .size: _order = State(initialValue: [KeyPathComparator(\FileItem.size, order: .reverse)])
        case .modified: _order = State(initialValue: [KeyPathComparator(\FileItem.sortDate, order: .reverse)])
        }
    }

    var body: some View {
        if showsFolder {
            Table(items.sorted(using: order), sortOrder: $order) {
                TableColumn("Name", value: \.name) { NameCell(item: $0) }.width(min: 160, ideal: 240)
                TableColumn("Folder", value: \.folder) { item in
                    Text(item.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                .width(min: 80, ideal: 170)
                TableColumn("Size", value: \.size) { SizeCell(item: $0) }.width(min: 70, ideal: 80)
                TableColumn("Modified", value: \.sortDate) { DateCell(item: $0) }.width(min: 90, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        } else {
            Table(items.sorted(using: order), sortOrder: $order) {
                TableColumn("Name", value: \.name) { NameCell(item: $0) }.width(min: 160, ideal: 300)
                TableColumn("Size", value: \.size) { SizeCell(item: $0) }.width(min: 70, ideal: 80)
                TableColumn("Items", value: \.itemCount) { item in
                    Text(item.isDirectory ? item.itemCount.formatted() : "").monospacedDigit().foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 60)
                TableColumn("Modified", value: \.sortDate) { DateCell(item: $0) }.width(min: 90, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

struct NameCell: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Format.icon(for: item)).resizable().frame(width: 16, height: 16)
            Text(item.name).lineLimit(1).truncationMode(.middle)
        }
        .opacity(item.isHidden ? 0.55 : 1)
    }
}

struct SizeCell: View {
    let item: FileItem

    var body: some View {
        Text(Format.bytes(item.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DateCell: View {
    let item: FileItem

    var body: some View {
        Text(item.modified.map(Format.relative) ?? "").foregroundStyle(.secondary).lineLimit(1)
    }
}

extension FileItem {
    var sortDate: Date { modified ?? .distantPast }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(noun)\(value == 1 ? "" : "s")"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func gitStatus(_ status: GitStatus) -> String {
        if status.isClean { return "clean" }
        return [status.modified > 0 ? "\(status.modified) modified" : nil, status.deleted > 0 ? "\(status.deleted) deleted" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }

    static func color(_ kind: FileKind) -> Color {
        switch kind {
        case .image: Color(red: 0.91, green: 0.36, blue: 0.55)
        case .video: Color(red: 0.55, green: 0.40, blue: 0.95)
        case .audio: Color(red: 0.97, green: 0.62, blue: 0.20)
        case .code: Color(red: 0.20, green: 0.56, blue: 0.98)
        case .document: Color(red: 0.24, green: 0.74, blue: 0.48)
        case .archive: Color(red: 0.70, green: 0.52, blue: 0.36)
        case .other: Color(nsColor: .systemGray)
        }
    }

    @MainActor static func icon(for item: FileItem) -> NSImage {
        if item.isDirectory { return NSWorkspace.shared.icon(for: .folder) }
        let ext = (item.path as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    @MainActor static func icon(for url: URL, content: PreviewModel.Content) -> NSImage {
        switch content {
        case .folder: NSWorkspace.shared.icon(forFile: url.path)
        case .zip: NSWorkspace.shared.icon(for: .zip)
        case .markdown: NSWorkspace.shared.icon(for: UTType(filenameExtension: "md") ?? .plainText)
        }
    }
}
