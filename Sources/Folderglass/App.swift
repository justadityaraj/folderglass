import AppKit
import FolderglassCore
import FolderglassUI
import SwiftUI

@main
struct FolderglassApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Folderglass", id: "main") {
            WelcomeView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Extension {
    static let identifier = "com.adityarajsingh.Folderglass.Preview"

    static var isEnabled: Bool {
        run("/usr/bin/pluginkit", ["-m", "-i", identifier]).hasPrefix("+")
    }

    static func enable() {
        _ = run("/usr/bin/pluginkit", ["-e", "ignore", "-i", "com.adityarajsingh.Foldout.Preview"])
        _ = run("/usr/bin/pluginkit", ["-e", "use", "-i", identifier])
        _ = run("/usr/bin/qlmanage", ["-r"])
        _ = run("/usr/bin/qlmanage", ["-r", "cache"])
    }

    static func reset() {
        let appex = Bundle.main.bundleURL.appending(path: "Contents/PlugIns/FolderglassPreview.appex")
        _ = run("/usr/bin/pluginkit", ["-a", appex.path])
        enable()
    }

    static func preview(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Updates {
    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    enum State: Equatable {
        case idle, checking, upToDate, failed, installing
        case available(version: String, page: URL, archive: URL?)
        case installFailed(page: URL)
    }

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let homebrewPrefix = SelfUpdate.homebrewPrefix(of: Bundle.main.bundleURL)

    @MainActor static func install(from archive: URL) async -> Bool {
        let app = Bundle.main.bundleURL
        guard (try? await SelfUpdate.install(from: archive, over: app)) != nil else { return false }
        Extension.reset()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? relaunch.run()
        NSApp.terminate(nil)
        return true
    }

    @MainActor static func upgradeWithHomebrew(prefix: URL) {
        let script = FileManager.default.temporaryDirectory.appending(path: "Update Folderglass.command")
        guard (try? Data(SelfUpdate.homebrewScript(prefix: prefix).utf8).write(to: script)) != nil,
              (try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)) != nil else { return }
        NSWorkspace.shared.open(script)
        NSApp.terminate(nil)
    }

    static func check() async -> State {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/justadityaraj/folderglass/releases/latest")!, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return .failed }
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let archive = release.assets.first { $0.name == "Folderglass.zip" }?.browser_download_url
        return Version.isNewer(version, than: current) ? .available(version: version, page: release.html_url, archive: archive) : .upToDate
    }
}

extension UserSettings.StartTab {
    var title: String {
        switch self {
        case .automatic: localized("Automatic")
        case .contents: localized("Contents")
        case .largest: localized("Largest")
        case .recent: localized("Recent")
        case .readme: localized("README")
        case .images: localized("Images")
        }
    }
}

extension UserSettings.ContentsSort {
    var title: String {
        switch self {
        case .size: localized("Size")
        case .name: localized("Name")
        case .modified: localized("Date Modified")
        case .items: localized("Item Count")
        }
    }
}

struct WelcomeView: View {
    @State private var enabled = Extension.isEnabled
    @State private var settings = UserSettings.load()
    @State private var update = Updates.State.idle
    @State private var didReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folderglass").font(.largeTitle.weight(.bold))
                    Text(localized("See inside any folder with Quick Look")).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(enabled ? .green : .orange)
                Text(enabled ? localized("Quick Look extension is on") : localized("Quick Look extension is off"))
                    .font(.headline)
                Spacer()
                if !enabled {
                    Button(localized("Turn On")) {
                        Extension.enable()
                        enabled = Extension.isEnabled
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 8) {
                Label(localized("Select a folder in Finder and press Space."), systemImage: "space")
                Label(localized("Git repos show the branch, last commit and changes."), systemImage: "arrow.triangle.branch")
                Label(localized("README, Markdown and zip files preview too."), systemImage: "doc.richtext")
            }
            .foregroundStyle(.secondary)

            settingsSection(localized("Preview")) {
                row(localized("Show hidden files")) { Toggle("", isOn: $settings.showHiddenFiles) }
                row(localized("Open on tab")) {
                    Picker("", selection: $settings.startTab) {
                        ForEach(UserSettings.StartTab.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                row(localized("Sort Contents by")) {
                    Picker("", selection: $settings.contentsSort) {
                        ForEach(UserSettings.ContentsSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
                row(localized("Stop counting after")) {
                    Picker("", selection: $settings.scanSeconds) {
                        ForEach([5, 15, 30], id: \.self) { Text(localized("\($0) seconds")).tag(Double($0)) }
                    }
                    .fixedSize()
                }
                row(localized("Count only the top level on network drives")) { Toggle("", isOn: $settings.skipNetworkDrives) }
            }

            settingsSection(localized("General")) {
                row(localized("Check for updates when Folderglass opens")) { Toggle("", isOn: $settings.checkForUpdates) }
                HStack {
                    Button(localized("Check for Updates")) { Task { update = .checking; update = await Updates.check() } }
                        .disabled(update == .checking || update == .installing)
                    Button(localized("Reset Quick Look")) {
                        Extension.reset()
                        enabled = Extension.isEnabled
                        didReset = true
                    }
                    Spacer()
                }
                updateStatus
            }

            HStack {
                Button(localized("Try It on a Folder…"), action: chooseFolder)
                Button(localized("Extension Settings…")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/justadityaraj/folderglass")!)
            }
        }
        .padding(24)
        .frame(width: 480)
        .task {
            if !enabled {
                Extension.enable()
                enabled = Extension.isEnabled
            }
            guard settings.checkForUpdates else { return }
            let result = await Updates.check()
            if case .available = result { update = result }
        }
        .onChange(of: settings) { _, new in try? new.save() }
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control().labelsHidden()
        }
    }

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content() }
                .toggleStyle(.switch)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch update {
        case .idle:
            if didReset { Text(localized("Quick Look was reset. Try pressing Space on a folder again.")).foregroundStyle(.secondary) }
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(localized("Checking…")).foregroundStyle(.secondary) }
        case .upToDate:
            Text(localized("Folderglass \(Updates.current) is the latest version.")).foregroundStyle(.secondary)
        case .failed:
            Text(localized("Couldn't reach GitHub to check for updates.")).foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(localized("Updating…")).foregroundStyle(.secondary) }
        case .installFailed(let page):
            HStack {
                Text(localized("The update couldn't be installed.")).foregroundStyle(.secondary)
                Spacer()
                Button(localized("Download")) { NSWorkspace.shared.open(page) }
            }
        case .available(let version, let page, let archive):
            HStack {
                Text(localized("Folderglass \(version) is available.")).fontWeight(.medium)
                Spacer()
                if let prefix = Updates.homebrewPrefix {
                    Button(localized("Update in Terminal")) { Updates.upgradeWithHomebrew(prefix: prefix) }
                        .keyboardShortcut(.defaultAction)
                } else if let archive, SelfUpdate.canReplace(Bundle.main.bundleURL) {
                    Button(localized("Update and Relaunch")) {
                        update = .installing
                        Task { if await !Updates.install(from: archive) { update = .installFailed(page: page) } }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(localized("Download")) { NSWorkspace.shared.open(page) }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Extension.preview(url)
    }
}
