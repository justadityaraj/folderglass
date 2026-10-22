import Foundation

public struct UserSettings: Codable, Equatable, Sendable {
    public enum StartTab: String, Codable, CaseIterable, Sendable {
        case automatic, contents, largest, recent, readme, images
    }

    public var checkForUpdates = true
    public var showHiddenFiles = false
    public var startTab = StartTab.automatic
    public var scanSeconds: Double = 15
    public var skipNetworkDrives = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserSettings()
        checkForUpdates = try values.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? defaults.checkForUpdates
        showHiddenFiles = try values.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? defaults.showHiddenFiles
        startTab = (try? values.decodeIfPresent(StartTab.self, forKey: .startTab)) ?? defaults.startTab
        scanSeconds = try values.decodeIfPresent(Double.self, forKey: .scanSeconds) ?? defaults.scanSeconds
        skipNetworkDrives = try values.decodeIfPresent(Bool.self, forKey: .skipNetworkDrives) ?? defaults.skipNetworkDrives
    }

    public static var fileURL: URL {
        URL(fileURLWithPath: FolderScanner.homeDirectory).appending(path: "Library/Application Support/Folderglass/settings.json")
    }

    public static func load(from url: URL = fileURL) -> UserSettings {
        guard let data = try? Data(contentsOf: url) else { return UserSettings() }
        return (try? JSONDecoder().decode(UserSettings.self, from: data)) ?? UserSettings()
    }

    public func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public enum Version {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
