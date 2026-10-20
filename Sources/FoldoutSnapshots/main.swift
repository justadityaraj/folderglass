import AppKit
import FoldoutUI
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: FoldoutSnapshots <path> <output.png> [light|dark] [width] [height] [tab]")
    exit(2)
}
let target = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let dark = arguments.count > 3 && arguments[3] == "dark"
let width = arguments.count > 4 ? Double(arguments[4]) ?? 820 : 820
let height = arguments.count > 5 ? Double(arguments[5]) ?? 600 : 600
let tab = arguments.count > 6 ? arguments[6] : nil

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

MainActor.assumeIsolated {
    let model = PreviewModel(url: target, content: PreviewModel.content(for: target))
    let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = app.appearance
    let host = NSHostingView(rootView: PreviewView(model: model, tab: tab))
    window.contentView = host
    window.orderFrontRegardless()

    Task { @MainActor in
        await model.load()
        try? await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: output)
        print("Wrote \(output.path)")
        exit(0)
    }
}
app.run()
