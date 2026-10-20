import Foundation

public struct FileItem: Sendable, Hashable, Identifiable {
    public let path: String
    public let size: Int64
    public let modified: Date?
    public let isDirectory: Bool
    public let itemCount: Int

    public init(path: String, size: Int64, modified: Date?, isDirectory: Bool, itemCount: Int = 0) {
        self.path = path
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.itemCount = itemCount
    }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var isHidden: Bool { path.split(separator: "/").contains { $0.hasPrefix(".") } }
    public var kind: FileKind { isDirectory ? .other : FileKind(fileExtension: (path as NSString).pathExtension) }
}

public struct KindTotal: Sendable, Hashable {
    public let kind: FileKind
    public var count: Int
    public var size: Int64
}

public struct FolderSummary: Sendable {
    public var fileCount = 0
    public var folderCount = 0
    public var totalSize: Int64 = 0
    public var latestModified: Date?
    public var kinds: [KindTotal] = []
    public var children: [FileItem] = []
    public var largest: [FileItem] = []
    public var recent: [FileItem] = []
    public var images: [FileItem] = []
    public var imageCount = 0
    public var childCount = 0
    public var readme: String?
    public var isComplete = false
    public var hitLimit = false

    public var isMostlyImages: Bool {
        let visible = kinds.reduce(0) { $0 + $1.count }
        return imageCount >= 4 && imageCount * 2 >= visible
    }
}

public struct FolderTally {
    public static let listLimit = 100
    public static let imageLimit = 120
    public static let childLimit = 500

    private var summary = FolderSummary()
    private var kinds: [FileKind: KindTotal] = [:]
    private var folders: [String: FileItem] = [:]
    private var topFiles: [FileItem] = []
    private var topFileCount = 0
    private var kindCache: [String: FileKind] = [:]
    private var largest: [FileItem] = []
    private var recent: [FileItem] = []
    private var images: [FileItem] = []

    public init() {}

    public mutating func add(_ item: FileItem) {
        let top = item.path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? item.path
        let isTopLevel = top == item.path

        if item.isDirectory {
            if !item.isHidden { summary.folderCount += 1 }
            if isTopLevel { mergeChild(top, size: 0, modified: nil, isDirectory: true, count: 0) }
            return
        }

        summary.totalSize = summary.totalSize.saturatingAdd(item.size)
        if isTopLevel {
            topFiles.append(item)
            topFileCount += 1
            if topFiles.count > Self.childLimit * 4 { trim() }
        } else {
            mergeChild(top, size: item.size, modified: item.modified, isDirectory: true, count: 1)
        }

        guard !item.isHidden else { return }
        summary.fileCount += 1
        if let modified = item.modified, modified > (summary.latestModified ?? .distantPast) { summary.latestModified = modified }
        let kind = kind(of: item)
        var total = kinds[kind] ?? KindTotal(kind: kind, count: 0, size: 0)
        total.count += 1
        total.size = total.size.saturatingAdd(item.size)
        kinds[kind] = total
        if isTopLevel, summary.readme == nil || item.name.lowercased().hasSuffix(".md"), Self.isReadme(item.name) {
            summary.readme = item.path
        }
        largest.append(item)
        recent.append(item)
        if largest.count > Self.listLimit * 4 { trim() }
        if kind == .image {
            summary.imageCount += 1
            if images.count < Self.imageLimit { images.append(item) }
        }
    }

    public mutating func markLimitHit() { summary.hitLimit = true }

    public func snapshot(complete: Bool) -> FolderSummary {
        var copy = self
        copy.trim()
        var result = copy.summary
        result.isComplete = complete
        result.kinds = kinds.values.sorted { ($0.size, $1.kind.rawValue) > ($1.size, $0.kind.rawValue) }
        result.children = Array((Array(folders.values) + copy.topFiles).sorted { $0.size > $1.size }.prefix(Self.childLimit))
        result.childCount = folders.count + topFileCount
        result.largest = copy.largest
        result.recent = copy.recent
        result.images = images.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return result
    }

    public static func isReadme(_ name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        return (lower as NSString).deletingPathExtension == "readme" && ["", "md", "markdown", "txt"].contains(ext)
    }

    private mutating func kind(of item: FileItem) -> FileKind {
        let ext = (item.path as NSString).pathExtension.lowercased()
        if let cached = kindCache[ext] { return cached }
        let kind = FileKind(fileExtension: ext)
        kindCache[ext] = kind
        return kind
    }

    private mutating func mergeChild(_ name: String, size: Int64, modified: Date?, isDirectory: Bool, count: Int) {
        let existing = folders[name]
        let latest = [existing?.modified, modified].compactMap { $0 }.max()
        folders[name] = FileItem(
            path: name,
            size: (existing?.size ?? 0).saturatingAdd(size),
            modified: latest,
            isDirectory: (existing?.isDirectory ?? false) || isDirectory,
            itemCount: (existing?.itemCount ?? 0) + count
        )
    }

    private mutating func trim() {
        largest = Array(largest.sorted { $0.size > $1.size }.prefix(Self.listLimit))
        recent = Array(recent.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }.prefix(Self.listLimit))
        topFiles = Array(topFiles.sorted { $0.size > $1.size }.prefix(Self.childLimit))
    }
}

public struct ScanLimits: Sendable {
    public var maxItems: Int
    public var maxDuration: TimeInterval

    public init(maxItems: Int = 1_000_000, maxDuration: TimeInterval = 15) {
        self.maxItems = maxItems
        self.maxDuration = maxDuration
    }
}

public enum FolderScanner {
    public static let skippedFolders: Set<String> = {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let library = [
            "CloudStorage", "Mobile Documents", "Photos", "Containers", "Group Containers", "Daemon Containers", "Mail", "Messages",
            "Safari", "Calendars", "Reminders", "Cookies", "HomeKit", "Suggestions", "Accounts", "Sharing", "Biome",
            "IdentityServices", "PersonalizationPortrait", "Metadata/CoreSpotlight", "Application Support/AddressBook",
            "Application Support/CallHistoryDB", "Application Support/CallHistoryTransactions", "Application Support/com.apple.TCC",
            "Application Support/MobileSync", "Application Support/Knowledge", "Application Support/FaceTime",
        ]
        return Set(library.map { "\(home)/Library/\($0)" })
    }()

    private static let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]

    public static func scan(
        _ root: URL,
        limits: ScanLimits = ScanLimits(),
        progressInterval: TimeInterval = 0.2,
        progress: (FolderSummary) -> Void = { _ in }
    ) -> FolderSummary {
        var tally = FolderTally()
        let start = Date()
        var lastReport = start
        var seen = 0
        var limited = false
        var package: (item: FileItem, level: Int)?
        let resolved = realpath(root.path, nil)
        defer { free(resolved) }
        let rootPaths = Set([root.standardizedFileURL.path, resolved.map { String(cString: $0) } ?? root.path])

        func flushPackage() {
            if let open = package { tally.add(open.item) }
            package = nil
        }

        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return tally.snapshot(complete: true)
        }

        while let url = walker.nextObject() as? URL {
            if Task.isCancelled { return tally.snapshot(complete: false) }
            seen += 1
            if seen > limits.maxItems || Date().timeIntervalSince(start) > limits.maxDuration {
                tally.markLimitHit()
                limited = true
                break
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let level = walker.level
            if let open = package, level <= open.level { flushPackage() }
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isSymbolicLink ?? false)
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate

            if let open = package {
                if !isDirectory {
                    let latest = [open.item.modified, modified].compactMap { $0 }.max()
                    package?.item = FileItem(path: open.item.path, size: open.item.size + size, modified: latest, isDirectory: false)
                }
            } else {
                let path = relativePath(of: url, under: rootPaths)
                if isDirectory && values?.isPackage == true {
                    package = (FileItem(path: path, size: 0, modified: nil, isDirectory: false), level)
                    if ["photoslibrary", "musiclibrary"].contains(url.pathExtension) { walker.skipDescendants() }
                } else {
                    if isDirectory, skippedFolders.contains(url.path) { walker.skipDescendants() }
                    tally.add(FileItem(path: path, size: isDirectory ? 0 : size, modified: modified, isDirectory: isDirectory))
                }
            }

            if Date().timeIntervalSince(lastReport) >= progressInterval {
                lastReport = Date()
                progress(tally.snapshot(complete: false))
            }
        }
        flushPackage()
        return tally.snapshot(complete: !limited)
    }

    static func relativePath(of url: URL, under rootPaths: Set<String>) -> String {
        let path = url.path
        let prefixes = rootPaths.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        guard let prefix = prefixes.first(where: { path.hasPrefix($0) }) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }
}

extension Int64 {
    func saturatingAdd(_ other: Int64) -> Int64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}
