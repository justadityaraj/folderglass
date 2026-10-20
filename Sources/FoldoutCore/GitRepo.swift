import Compression
import CryptoKit
import Foundation

public struct GitCommit: Sendable, Equatable {
    public let hash: String
    public let subject: String
    public let author: String
    public let date: Date?
}

public struct GitStatus: Sendable, Equatable {
    public let modified: Int
    public let deleted: Int

    public init(modified: Int, deleted: Int) {
        self.modified = modified
        self.deleted = deleted
    }

    public var isClean: Bool { modified == 0 && deleted == 0 }
}

public struct GitInfo: Sendable {
    public let branch: String?
    public let head: String?
    public let lastCommit: GitCommit?
    public let status: GitStatus?
    public let remote: String?
}

public enum GitReader {
    public static func read(_ root: URL, statusBudget: TimeInterval = 3) -> GitInfo? {
        guard let gitDir = gitDirectory(for: root) else { return nil }
        let commonDir = commonDirectory(for: gitDir)
        let headRef = text(gitDir.appending(path: "HEAD"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        var branch: String?
        var head: String?
        if let headRef, headRef.hasPrefix("ref: ") {
            let ref = String(headRef.dropFirst(5))
            branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : ref
            head = resolve(ref, in: commonDir)
        } else if let headRef, headRef.count == 40 {
            head = headRef
        }
        let commit = head.flatMap { commitInfo($0, in: commonDir) } ?? reflogCommit(gitDir, head: head)
        return GitInfo(
            branch: branch,
            head: head,
            lastCommit: commit,
            status: status(root: root, gitDir: gitDir, budget: statusBudget),
            remote: remote(in: commonDir)
        )
    }

    static func gitDirectory(for root: URL) -> URL? {
        let dotGit = root.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        guard let pointer = text(dotGit)?.trimmingCharacters(in: .whitespacesAndNewlines), pointer.hasPrefix("gitdir: ") else { return nil }
        let path = String(pointer.dropFirst(8))
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path).standardizedFileURL
    }

    static func commonDirectory(for gitDir: URL) -> URL {
        guard let common = text(gitDir.appending(path: "commondir"))?.trimmingCharacters(in: .whitespacesAndNewlines) else { return gitDir }
        return common.hasPrefix("/") ? URL(fileURLWithPath: common) : gitDir.appending(path: common).standardizedFileURL
    }

    static func resolve(_ ref: String, in commonDir: URL) -> String? {
        if let loose = text(commonDir.appending(path: ref))?.trimmingCharacters(in: .whitespacesAndNewlines), loose.count == 40 {
            return loose
        }
        guard let packed = text(commonDir.appending(path: "packed-refs")) else { return nil }
        for line in packed.split(separator: "\n") where line.hasSuffix(" " + ref) {
            return String(line.prefix(40))
        }
        return nil
    }

    static func remote(in commonDir: URL) -> String? {
        guard let config = text(commonDir.appending(path: "config")) else { return nil }
        var inOrigin = false
        for raw in config.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line == "[remote \"origin\"]"; continue }
            guard inOrigin, line.hasPrefix("url") else { continue }
            guard let value = line.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) else { continue }
            return displayRemote(value)
        }
        return nil
    }

    public static func displayRemote(_ url: String) -> String {
        var value = url
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let at = value.firstIndex(of: "@"), !value[..<at].contains("/") { value = String(value[value.index(after: at)...]) }
        if let colon = value.firstIndex(of: ":"), !value[..<colon].contains("/") {
            value.replaceSubrange(colon...colon, with: "/")
        }
        return value
    }

    static func commitInfo(_ hash: String, in commonDir: URL) -> GitCommit? {
        guard let body = object(hash, in: commonDir), let content = String(data: body, encoding: .utf8) else { return nil }
        let parts = content.components(separatedBy: "\n\n")
        guard let header = parts.first else { return nil }
        var author = ""
        var date: Date?
        for line in header.split(separator: "\n") where line.hasPrefix("author ") {
            let fields = line.dropFirst(7)
            if let open = fields.firstIndex(of: "<") {
                author = fields[..<open].trimmingCharacters(in: .whitespaces)
            }
            let tail = fields.split(separator: " ")
            if tail.count >= 2, let seconds = TimeInterval(tail[tail.count - 2]) { date = Date(timeIntervalSince1970: seconds) }
        }
        let message = parts.dropFirst().joined(separator: "\n\n")
        let subject = message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return GitCommit(hash: hash, subject: subject, author: author, date: date)
    }

    static func reflogCommit(_ gitDir: URL, head: String?) -> GitCommit? {
        guard let log = text(gitDir.appending(path: "logs/HEAD")),
              let line = log.split(separator: "\n").last,
              let tab = line.firstIndex(of: "\t") else { return nil }
        let meta = line[..<tab].split(separator: " ")
        guard meta.count >= 4 else { return nil }
        let message = String(line[line.index(after: tab)...])
        let subject = message.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? message
        let nameEnd = meta.firstIndex { $0.hasPrefix("<") } ?? 2
        return GitCommit(
            hash: head ?? String(meta[1]),
            subject: subject,
            author: meta[2..<nameEnd].joined(separator: " "),
            date: TimeInterval(meta[meta.count - 2]).map { Date(timeIntervalSince1970: $0) }
        )
    }

    static func object(_ hash: String, in commonDir: URL) -> Data? {
        let objects = commonDir.appending(path: "objects")
        let loose = objects.appending(path: String(hash.prefix(2))).appending(path: String(hash.dropFirst(2)))
        if let compressed = try? Data(contentsOf: loose), let raw = inflate(compressed, capacity: 1 << 20),
           let nul = raw.firstIndex(of: 0), raw.prefix(upTo: nul).starts(with: Data("commit".utf8)) {
            return raw.suffix(from: nul + 1)
        }
        guard let sha = Data(hex: hash),
              let packs = try? FileManager.default.contentsOfDirectory(at: objects.appending(path: "pack"), includingPropertiesForKeys: nil) else { return nil }
        for idx in packs where idx.pathExtension == "idx" {
            guard let offset = packOffset(of: sha, idx: idx) else { continue }
            return packedCommit(at: offset, pack: idx.deletingPathExtension().appendingPathExtension("pack"))
        }
        return nil
    }

    static func packOffset(of sha: Data, idx: URL) -> UInt64? {
        guard let data = try? Data(contentsOf: idx, options: .alwaysMapped), data.count > 1032,
              data.prefix(4) == Data([0xFF, 0x74, 0x4F, 0x63]), data.uint32(at: 4) == 2 else { return nil }
        let first = Int(sha[sha.startIndex])
        let total = Int(data.uint32(at: 8 + 255 * 4))
        var low = first == 0 ? 0 : Int(data.uint32(at: 8 + (first - 1) * 4))
        var high = Int(data.uint32(at: 8 + first * 4))
        let names = 8 + 256 * 4
        while low < high {
            let mid = (low + high) / 2
            let start = names + mid * 20
            let candidate = data.subdata(in: start..<start + 20)
            if candidate == sha {
                let offsets = names + total * 24
                let small = data.uint32(at: offsets + mid * 4)
                guard small & 0x8000_0000 != 0 else { return UInt64(small) }
                let large = offsets + total * 4 + Int(small & 0x7FFF_FFFF) * 8
                return UInt64(data.uint32(at: large)) << 32 | UInt64(data.uint32(at: large + 4))
            }
            if candidate.lexicographicallyPrecedes(sha) { low = mid + 1 } else { high = mid }
        }
        return nil
    }

    static func packedCommit(at offset: UInt64, pack: URL) -> Data? {
        guard let data = try? Data(contentsOf: pack, options: .alwaysMapped), offset < data.count else { return nil }
        var position = data.startIndex + Int(offset)
        var byte = data[position]
        guard (byte >> 4) & 0x7 == 1 else { return nil }
        var size = Int(byte & 0x0F)
        var shift = 4
        while byte & 0x80 != 0 {
            position += 1
            byte = data[position]
            size |= Int(byte & 0x7F) << shift
            shift += 7
        }
        position += 1
        let end = min(data.endIndex, position + size + 4096)
        return inflate(data.subdata(in: position..<end), capacity: size)
    }

    static func inflate(_ zlib: Data, capacity: Int) -> Data? {
        guard zlib.count > 2, capacity > 0 else { return nil }
        let deflated = zlib.dropFirst(2)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { out in
            deflated.withUnsafeBytes { input in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    input.bindMemory(to: UInt8.self).baseAddress!, deflated.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return written > 0 ? output.prefix(written) : nil
    }

    static func status(root: URL, gitDir: URL, budget: TimeInterval) -> GitStatus? {
        guard let index = try? Data(contentsOf: gitDir.appending(path: "index"), options: .alwaysMapped),
              index.count >= 12, index.prefix(4) == Data("DIRC".utf8) else { return nil }
        let version = index.uint32(at: 4)
        guard version == 2 || version == 3 else { return nil }
        let count = Int(index.uint32(at: 8))
        let started = Date()
        var position = 12
        var modified = 0
        var deleted = 0

        for _ in 0..<count {
            guard position + 62 <= index.count else { return nil }
            if Date().timeIntervalSince(started) > budget { return nil }
            let mtime = index.uint32(at: position + 8)
            let mtimeNanos = index.uint32(at: position + 12)
            let mode = index.uint32(at: position + 24)
            let size = index.uint32(at: position + 36)
            let sha = index.subdata(in: index.startIndex + position + 40..<index.startIndex + position + 60)
            let flags = UInt16(index[index.startIndex + position + 60]) << 8 | UInt16(index[index.startIndex + position + 61])
            let extended = version == 3 && flags & 0x4000 != 0
            let extraFlags: UInt16 = extended
                ? UInt16(index[index.startIndex + position + 62]) << 8 | UInt16(index[index.startIndex + position + 63])
                : 0
            let nameStart = position + (extended ? 64 : 62)
            guard let nul = index[(index.startIndex + nameStart)...].firstIndex(of: 0) else { return nil }
            let path = String(decoding: index[(index.startIndex + nameStart)..<nul], as: UTF8.self)
            let nameLength = nul - index.startIndex - nameStart
            position += ((nameStart - position) + nameLength + 8) & ~7

            let stage = (flags >> 12) & 0x3
            let skip = stage != 0 || flags & 0x8000 != 0 || extraFlags & 0x4000 != 0 || mode & 0o170000 == 0o160000
            if skip { continue }

            var info = stat()
            guard lstat(root.appending(path: path).path, &info) == 0 else {
                deleted += 1
                continue
            }
            if UInt32(truncatingIfNeeded: info.st_size) != size {
                modified += 1
            } else if UInt32(truncatingIfNeeded: info.st_mtimespec.tv_sec) != mtime
                        || (mtimeNanos != 0 && UInt32(truncatingIfNeeded: info.st_mtimespec.tv_nsec) != mtimeNanos) {
                if mode & 0o170000 == 0o120000 || blobHash(root.appending(path: path), size: Int(size)) != sha { modified += 1 }
            }
        }
        return GitStatus(modified: modified, deleted: deleted)
    }

    static func blobHash(_ file: URL, size: Int) -> Data? {
        guard size <= 16 << 20, let content = try? Data(contentsOf: file) else { return nil }
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(content.count)\0".utf8))
        hasher.update(data: content)
        return Data(hasher.finalize())
    }

    static func text(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    func uint32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return self[start..<start + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
