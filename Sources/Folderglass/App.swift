import AppKit
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

struct WelcomeView: View {
    @State private var enabled = Extension.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folderglass").font(.largeTitle.weight(.bold))
                    Text("See inside any folder with Quick Look").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(enabled ? .green : .orange)
                Text(enabled ? "Quick Look extension is on" : "Quick Look extension is off")
                    .font(.headline)
                Spacer()
                if !enabled {
                    Button("Turn On") {
                        Extension.enable()
                        enabled = Extension.isEnabled
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 8) {
                Label("Select a folder in Finder and press Space.", systemImage: "space")
                Label("Git repos show the branch, last commit and changes.", systemImage: "arrow.triangle.branch")
                Label("README, Markdown and zip files preview too.", systemImage: "doc.richtext")
            }
            .foregroundStyle(.secondary)

            HStack {
                Button("Try It on a Folder…", action: chooseFolder)
                Button("Extension Settings…") {
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
