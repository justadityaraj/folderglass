import Foundation
import FoldoutCore

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if !condition {
        failures += 1
        print("FAIL: \(name)")
    }
}

@discardableResult
func run(_ arguments: [String], in directory: URL) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func write(_ text: String, to url: URL, modified: Date? = nil) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
    if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
}

let root = FileManager.default.temporaryDirectory.appending(path: "foldout-selfcheck-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }

let old = Date(timeIntervalSince1970: 1_600_000_000)
write(String(repeating: "x", count: 5000), to: root.appending(path: "assets/big.png"), modified: old)
write(String(repeating: "y", count: 300), to: root.appending(path: "assets/small.jpg"), modified: old)
write("print(1)", to: root.appending(path: "src/main.swift"))
write("# Demo\n\nHello", to: root.appending(path: "README.md"), modified: old)
write("secret", to: root.appending(path: ".env"), modified: old)
write(String(repeating: "z", count: 900), to: root.appending(path: "Tool.app/Contents/MacOS/Tool"), modified: old)
write("{}", to: root.appending(path: "Tool.app/Contents/Info.plist"), modified: old)

var progressCalls = 0
let summary = FolderScanner.scan(root, progressInterval: 0) { _ in progressCalls += 1 }
check(summary.isComplete && !summary.hitLimit, "scan completes")
check(summary.fileCount == 5, "packages count as one file and hidden files stay out of the count (got \(summary.fileCount))")
check(summary.folderCount == 2, "folders outside packages are counted (got \(summary.folderCount))")
check(summary.totalSize == 5000 + 300 + 8 + 13 + 6 + 902, "total size includes subfolders, hidden files and package contents (got \(summary.totalSize))")
check(summary.largest.first?.path == "assets/big.png", "largest file comes first")
check(summary.largest.contains { $0.path == "Tool.app" && $0.size == 902 }, "package appears as one sized item")
check(!summary.largest.contains { $0.path.hasPrefix(".") || $0.path.contains("Tool.app/") }, "hidden and package internals stay out of lists")
check(summary.recent.first?.path == "src/main.swift", "most recent file comes first")
check(summary.children.first?.path == "assets" && summary.children.first?.size == 5300, "top-level folders carry recursive size")
check(summary.children.first?.itemCount == 2, "top-level folders carry recursive file count")
check(summary.children.contains { $0.path == ".env" }, "hidden top-level items stay visible in contents")
check(summary.readme == "README.md", "readme detected")
check(summary.kinds.first?.kind == .image && summary.kinds.first?.count == 2, "images lead the type breakdown by size")
check(summary.imageCount == 2 && summary.images.map(\.name) == ["big.png", "small.jpg"], "images collected for the grid in name order")
check(progressCalls > 0, "progress reported while scanning")

let limited = FolderScanner.scan(root, limits: ScanLimits(maxItems: 2))
check(limited.hitLimit && !limited.isComplete, "item limit stops the scan")

check(FileKind(fileExtension: "PNG") == .image, "image kind is case-insensitive")
check(FileKind(fileExtension: "tsx") == .code, "tsx is code")
check(FileKind(fileExtension: "mp4") == .video, "mp4 is video")
check(FileKind(fileExtension: "zip") == .archive, "zip is archive")
check(FileKind(fileExtension: "md") == .document, "markdown is a document")
check(FileKind(fileExtension: "") == .other, "no extension is other")

let repo = root.appending(path: "repo")
write("one\n", to: repo.appending(path: "a.txt"))
write("two\n", to: repo.appending(path: "b.txt"))
write("three\n", to: repo.appending(path: "c.txt"))
let git = ["git", "-c", "user.name=Alex Doe", "-c", "user.email=alex@example.com", "-c", "commit.gpgsign=false"]
run(["git", "init", "-q", "-b", "main"], in: repo)
run(["git", "remote", "add", "origin", "git@github.com:acme/web.git"], in: repo)
run(["git", "add", "."], in: repo)
run(git + ["commit", "-q", "-m", "Initial commit"], in: repo)
run(git + ["commit", "-q", "--allow-empty", "-m", "Add the landing page", "-m", "Body text"], in: repo)

let loose = GitReader.read(repo)
check(loose?.branch == "main", "branch from HEAD")
check(loose?.lastCommit?.subject == "Add the landing page", "subject from a loose commit object (got \(loose?.lastCommit?.subject ?? "nil"))")
check(loose?.lastCommit?.author == "Alex Doe", "author from commit")
check(loose?.lastCommit?.date != nil, "commit date parsed")
check(loose?.status == GitStatus(modified: 0, deleted: 0), "fresh checkout is clean (got \(String(describing: loose?.status)))")
check(loose?.remote == "github.com/acme/web", "origin remote shown as host/path")

run(["git", "gc", "-q", "--aggressive"], in: repo)
let packed = GitReader.read(repo)
check(packed?.lastCommit?.subject == "Add the landing page", "subject from a packed commit object")
check(packed?.head == loose?.head && packed?.head?.count == 40, "head resolves through packed-refs")

write("one\n", to: repo.appending(path: "a.txt"), modified: Date(timeIntervalSinceNow: 60))
write("changed\n", to: repo.appending(path: "b.txt"))
try? FileManager.default.removeItem(at: repo.appending(path: "c.txt"))
let dirty = GitReader.read(repo)
check(dirty?.status == GitStatus(modified: 1, deleted: 1), "touched-but-same file is clean, edits and deletes count (got \(String(describing: dirty?.status)))")

run(["git", "checkout", "-q", "--detach"], in: repo)
check(GitReader.read(repo)?.branch == nil, "detached HEAD has no branch")
check(GitReader.read(root.appending(path: "assets")) == nil, "plain folder is not a repo")
check(GitReader.displayRemote("https://github.com/acme/web.git") == "github.com/acme/web", "https remote display")

let worktree = root.appending(path: "wt")
run(["git", "worktree", "add", "-q", "-b", "feature", worktree.path], in: repo)
check(GitReader.read(worktree)?.branch == "feature", "linked worktree reads its own branch")

let zip = root.appending(path: "bundle.zip")
run(["ditto", "-c", "-k", "--keepParent", root.appending(path: "assets").path, zip.path], in: root)
let zipped = ZipListing.summary(of: zip)
check(zipped?.fileCount == 2, "zip lists its files (got \(String(describing: zipped?.fileCount)))")
check(zipped?.totalSize == 5300, "zip reports uncompressed size")
check(zipped?.largest.first?.path == "big.png", "zip with one top folder is unwrapped")
check(zipped?.folderCount == 0, "unwrapped zip has no folders left")
check(ZipListing.summary(of: root.appending(path: "README.md")) == nil, "non-zip is rejected")

let markdown = """
# Title

Hello **world** and `code`.

<p align="center"><img src="logo.png"></p>

- one
- two
  1. nested

> quoted

```swift
let x = 1
```

---

| Name | Size |
|------|------|
| a    | 1    |
"""
let blocks = MarkdownDocument.blocks(from: markdown)
let kinds = blocks.map(\.kind)
check(kinds.first == .heading(1) && blocks.first?.plainText == "Title", "heading block")
check(blocks.contains { $0.kind == .paragraph && $0.plainText == "Hello world and code." }, "paragraph keeps inline text")
check(!blocks.contains { $0.plainText.contains("<") }, "html is stripped")
check(kinds.contains(.listItem(marker: "•", depth: 1)), "bullet list item")
check(kinds.contains(.listItem(marker: "1.", depth: 2)), "nested ordered list item")
check(kinds.contains(.quote), "block quote")
check(blocks.contains { $0.kind == .code(language: "swift") && $0.plainText == "let x = 1" }, "fenced code block")
check(kinds.contains(.rule), "thematic break")
check(blocks.contains { $0.kind == .tableRow(header: true) && $0.cells.count == 2 }, "table header row with two cells")
check(blocks.contains { $0.kind == .tableRow(header: false) && $0.cells.map { String($0.characters) } == ["a", "1"] }, "table body row cells")

let tricky = MarkdownDocument.blocks(from: "Use `Result<Value, Error>` here.\n\nSee <https://example.com> and if a < b and c > d.\n\n    Array<Int>\n\n<div align=\"center\">Centered</div>")
let trickyText = tricky.map(\.plainText).joined(separator: "|")
check(trickyText.contains("Result<Value, Error>"), "generics inside inline code survive (got \(trickyText))")
check(trickyText.contains("example.com"), "autolinks survive")
check(trickyText.contains("a < b and c > d"), "comparison operators survive")
check(trickyText.contains("Array<Int>"), "indented code survives")
check(trickyText.contains("Centered") && !trickyText.contains("<div"), "known html tags are still stripped")

let rootChildren = FolderScanner.scan(root, limits: ScanLimits(maxItems: 50))
check(rootChildren.childCount >= rootChildren.children.count, "child count covers listed children")

var flat = FolderTally()
for index in 0..<(FolderTally.childLimit + 50) { flat.add(FileItem(path: "f\(index).txt", size: Int64(index), modified: nil, isDirectory: false)) }
flat.add(FileItem(path: "huge.bin", size: .max, modified: nil, isDirectory: false))
let flatSummary = flat.snapshot(complete: true)
check(flatSummary.children.count == FolderTally.childLimit && flatSummary.childCount == FolderTally.childLimit + 51, "top-level list is capped but counted")
check(flatSummary.children.first?.path == "huge.bin" && flatSummary.totalSize == .max, "sizes saturate instead of overflowing")

let badGit = root.appending(path: "badgit")
write("ref: refs/heads/main\n", to: badGit.appending(path: ".git/HEAD"))
write("<x 0000 1 +0000\tcommit: broken\n", to: badGit.appending(path: ".git/logs/HEAD"))
try? Data([0x44, 0x49, 0x52, 0x43, 0, 0, 0, 3, 0, 0, 0, 1] + [UInt8](repeating: 0, count: 60) + [0x40, 0]).write(to: badGit.appending(path: ".git/index"))
try? FileManager.default.createDirectory(at: badGit.appending(path: ".git/objects/pack"), withIntermediateDirectories: true)
try? Data([0xFF, 0x74, 0x4F, 0x63, 0, 0, 0, 2] + [UInt8](repeating: 0xFF, count: 1100)).write(to: badGit.appending(path: ".git/objects/pack/x.idx"))
write("0123456789012345678901234567890123456789 refs/heads/main\n", to: badGit.appending(path: ".git/packed-refs"))
check(GitReader.read(badGit)?.branch == "main", "truncated index, bad pack index and odd reflog don't crash")

var zipBytes = Data([0x50, 0x4B, 0x06, 0x07, 0, 0, 0, 0] + [UInt8](repeating: 0xFF, count: 8) + [1, 0, 0, 0])
zipBytes += Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0])
try? zipBytes.write(to: root.appending(path: "bad.zip"))
check(ZipListing.summary(of: root.appending(path: "bad.zip")).map { $0.fileCount == 0 } ?? true, "zip64 offsets past the file don't crash")

if failures == 0 {
    print("All checks passed")
} else {
    print("\(failures) check(s) failed")
    exit(1)
}
