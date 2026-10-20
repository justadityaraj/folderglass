import Foundation

public enum ZipListing {
    public static func summary(of url: URL) -> FolderSummary? {
        guard let items = entries(of: url).map(unwrappingSingleFolder) else { return nil }
        var tally = FolderTally()
        var folders = Set<String>()
        for item in items where item.isDirectory { folders.insert(item.path) }
        for item in items {
            var parent = (item.path as NSString).deletingLastPathComponent
            while !parent.isEmpty, folders.insert(parent).inserted {
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        for folder in folders.sorted() { tally.add(FileItem(path: folder, size: 0, modified: nil, isDirectory: true)) }
        for item in items where !item.isDirectory { tally.add(item) }
        return tally.snapshot(complete: true)
    }

    static func unwrappingSingleFolder(_ items: [FileItem]) -> [FileItem] {
        let tops = Set(items.map { $0.path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0.path })
        guard tops.count == 1, let top = tops.first, items.contains(where: { $0.path.hasPrefix(top + "/") }),
              !items.contains(where: { $0.path == top && !$0.isDirectory }) else { return items }
        return items.compactMap { item in
            guard item.path.hasPrefix(top + "/") else { return nil }
            return FileItem(path: String(item.path.dropFirst(top.count + 1)), size: item.size, modified: item.modified, isDirectory: item.isDirectory)
        }
    }

    public static func entries(of url: URL) -> [FileItem]? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), let directory = centralDirectory(in: data) else { return nil }
        var items: [FileItem] = []
        var position = directory.offset
        for _ in 0..<directory.count {
            guard position + 46 <= data.count, data.le32(at: position) == 0x0201_4B50 else { break }
            let time = data.le16(at: position + 12)
            let date = data.le16(at: position + 14)
            var size = UInt64(data.le32(at: position + 24))
            let nameLength = Int(data.le16(at: position + 28))
            let extraLength = Int(data.le16(at: position + 30))
            let commentLength = Int(data.le16(at: position + 32))
            let nameStart = position + 46
            guard nameStart + nameLength + extraLength <= data.count else { break }
            let rawName = String(decoding: data[(data.startIndex + nameStart)..<(data.startIndex + nameStart + nameLength)], as: UTF8.self)
            if size == 0xFFFF_FFFF, let large = zip64Size(data, extraStart: nameStart + nameLength, length: extraLength) { size = large }
            position = nameStart + nameLength + extraLength + commentLength

            guard !rawName.hasPrefix("__MACOSX/"), !(rawName as NSString).lastPathComponent.hasPrefix("._") else { continue }
            let isDirectory = rawName.hasSuffix("/")
            let path = isDirectory ? String(rawName.dropLast()) : rawName
            guard !path.isEmpty else { continue }
            items.append(FileItem(path: path, size: isDirectory ? 0 : Int64(size), modified: dosDate(date: date, time: time), isDirectory: isDirectory))
        }
        return items
    }

    static func centralDirectory(in data: Data) -> (offset: Int, count: Int)? {
        guard data.count >= 22 else { return nil }
        var position = data.count - 22
        let floor = max(0, data.count - 22 - 0xFFFF)
        while position >= floor, data.le32(at: position) != 0x0605_4B50 { position -= 1 }
        guard position >= floor else { return nil }
        var count = Int(data.le16(at: position + 10))
        var offset = Int(data.le32(at: position + 16))
        if (count == 0xFFFF || offset == 0xFFFF_FFFF), position >= 20, data.le32(at: position - 20) == 0x0706_4B50 {
            let record = Int(data.le64(at: position - 12))
            if record + 56 <= data.count, data.le32(at: record) == 0x0606_4B50 {
                count = Int(data.le64(at: record + 32))
                offset = Int(data.le64(at: record + 48))
            }
        }
        return offset < data.count ? (offset, count) : nil
    }

    static func zip64Size(_ data: Data, extraStart: Int, length: Int) -> UInt64? {
        var position = extraStart
        while position + 4 <= extraStart + length {
            let id = data.le16(at: position)
            let size = Int(data.le16(at: position + 2))
            if id == 0x0001, size >= 8 { return data.le64(at: position + 4) }
            position += 4 + size
        }
        return nil
    }

    static func dosDate(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var parts = DateComponents()
        parts.year = Int(date >> 9) + 1980
        parts.month = Int((date >> 5) & 0xF)
        parts.day = Int(date & 0x1F)
        parts.hour = Int(time >> 11)
        parts.minute = Int((time >> 5) & 0x3F)
        parts.second = Int(time & 0x1F) * 2
        return Calendar.current.date(from: parts)
    }
}

extension Data {
    func le16(at offset: Int) -> UInt16 {
        let start = startIndex + offset
        return UInt16(self[start]) | UInt16(self[start + 1]) << 8
    }

    func le32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return (0..<4).reduce(0) { $0 | UInt32(self[start + $1]) << (8 * $1) }
    }

    func le64(at offset: Int) -> UInt64 {
        UInt64(le32(at: offset)) | UInt64(le32(at: offset + 4)) << 32
    }
}
