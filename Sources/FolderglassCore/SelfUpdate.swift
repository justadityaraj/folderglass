import Foundation
import Security

public enum SelfUpdate {
    public enum Problem: Error, Equatable {
        case download, unpack, unsigned, wrongSigner, notNewer
    }

    public static func canReplace(_ app: URL) -> Bool {
        let folder = app.deletingLastPathComponent()
        let readOnly = (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
        return !readOnly
            && !app.pathComponents.contains("AppTranslocation")
            && FileManager.default.isWritableFile(atPath: folder.path)
            && FileManager.default.isWritableFile(atPath: app.path)
    }

    public static func problem(installing candidate: URL, over installed: URL) -> Problem? {
        guard let team = teamIdentifier(of: installed),
              let identifier = Bundle(url: installed)?.bundleIdentifier else { return .unsigned }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess
        else { return .wrongSigner }
        let current = readVersion(of: installed) ?? "0"
        let offered = readVersion(of: candidate) ?? "0"
        return Version.isNewer(offered, than: current) ? nil : .notNewer
    }

    public static func unpack(_ archive: URL, into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard process.terminationStatus == 0, let app = contents.first(where: { $0.pathExtension == "app" }) else { throw Problem.unpack }
        return app
    }

    public static func install(from archive: URL, over app: URL) async throws {
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let (download, response) = try await URLSession.shared.download(from: archive)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Problem.download }
        let candidate = try unpack(download, into: work.appending(path: "unpacked"))
        if let problem = problem(installing: candidate, over: app) { throw problem }
        _ = try FileManager.default.replaceItemAt(app, withItemAt: candidate)
    }

    public static func homebrewPrefix(of app: URL) -> URL? {
        let path = app.resolvingSymlinksInPath().path
        guard let range = path.range(of: "/Cellar/folderglass/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]))
    }

    public static func homebrewScript(prefix: URL) -> String {
        let brew = quoted(prefix.appending(path: "bin/brew").path)
        let app = quoted(prefix.appending(path: "opt/folderglass/Folderglass.app").path)
        return "#!/bin/sh\n\(brew) upgrade folderglass && open \(app)\n"
    }

    static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func readVersion(of app: URL) -> String? {
        let plist = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
