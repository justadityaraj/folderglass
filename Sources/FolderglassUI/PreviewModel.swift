import AppKit
import FolderglassCore

@MainActor
public final class PreviewModel: ObservableObject {
    public enum Content: Sendable {
        case folder, zip, markdown
    }

    public let url: URL
    public let content: Content
    public let icon: NSImage
    @Published public private(set) var summary: FolderSummary?
    @Published public private(set) var git: GitInfo?
    @Published public private(set) var readme: [MarkdownBlock] = []
    @Published public private(set) var readmeName: String?
    @Published public private(set) var failed = false
    @Published public private(set) var topLevelOnly = false
    public let settings = UserSettings.load()
    private var task: Task<Void, Never>?
    private var scanFinished = false

    public init(url: URL, content: Content) {
        self.url = url
        self.content = content
        icon = Format.icon(for: url, content: content)
    }

    public nonisolated static func content(for url: URL) -> Content {
        switch url.pathExtension.lowercased() {
        case "zip": .zip
        case "md", "markdown", "mdown", "mkd": .markdown
        default: .folder
        }
    }

    public var title: String { FileManager.default.displayName(atPath: url.path) }

    public func start() {
        task = Task { await load() }
    }

    public func cancel() {
        task?.cancel()
    }

    public func load() async {
        let url = url
        switch content {
        case .markdown:
            readme = await Task.detached { Self.markdown(at: url) }.value
            readmeName = url.lastPathComponent
        case .zip:
            let job = Task.detached(priority: .utility) { ZipListing.summary(of: url) }
            summary = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            failed = summary == nil
        case .folder:
            async let details: (GitInfo?, String?, [MarkdownBlock]) = Task.detached { Self.details(of: url) }.value
            var limits = ScanLimits(maxDuration: settings.scanSeconds)
            if settings.skipNetworkDrives, (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false {
                limits.maxDepth = 1
                topLevelOnly = true
            }
            let includeHidden = settings.showHiddenFiles
            let scan = Task.detached(priority: .utility) { [weak self, limits] in
                FolderScanner.scan(url, limits: limits, includeHidden: includeHidden, progressInterval: 0.5) { partial in
                    Task { @MainActor in
                        if self?.scanFinished == false { self?.summary = partial }
                    }
                }
            }
            let (git, readmeName, readme) = await details
            self.git = git
            self.readmeName = readmeName
            self.readme = readme
            var timer: Task<Void, Never>?
            let finished: FolderSummary? = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    var resumed = false
                    func finish(_ result: FolderSummary?) {
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(returning: result)
                    }
                    Task { @MainActor in finish(await scan.value) }
                    timer = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(limits.maxDuration + 2))
                        finish(nil)
                    }
                }
            } onCancel: {
                scan.cancel()
            }
            timer?.cancel()
            scanFinished = true
            if let finished {
                summary = finished
            } else {
                scan.cancel()
                summary?.hitLimit = true
            }
        }
    }

    nonisolated static func details(of url: URL) -> (GitInfo?, String?, [MarkdownBlock]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let readme = names.filter(FolderTally.isReadme).sorted { $0.lowercased().hasSuffix(".md") && !$1.lowercased().hasSuffix(".md") }.first
        let blocks = readme.map { markdown(at: url.appending(path: $0)) } ?? []
        return (GitReader.read(url), readme, blocks)
    }

    nonisolated static func markdown(at url: URL) -> [MarkdownBlock] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 512 * 1024)) ?? Data()
        return MarkdownDocument.blocks(from: String(decoding: data, as: UTF8.self))
    }
}
