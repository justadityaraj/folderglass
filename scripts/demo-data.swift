import AppKit

let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/demo")
let fm = FileManager.default
try? fm.removeItem(at: base)

func write(_ path: String, _ text: String, in root: URL, daysAgo: Double = 0) {
    let url = root.appending(path: path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
    touch(url, daysAgo: daysAgo)
}

func blob(_ path: String, megabytes: Double, in root: URL, daysAgo: Double = 0) {
    let url = root.appending(path: path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var bytes = [UInt8](repeating: 0, count: Int(megabytes * 1_048_576))
    for index in stride(from: 0, to: bytes.count, by: 4096) { bytes[index] = UInt8(index % 251) }
    try? Data(bytes).write(to: url)
    touch(url, daysAgo: daysAgo)
}

func touch(_ url: URL, daysAgo: Double) {
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -daysAgo * 86_400)], ofItemAtPath: url.path)
}

func image(_ path: String, hue: CGFloat, in root: URL, size: CGSize = CGSize(width: 1600, height: 1067), daysAgo: Double = 0) {
    let url = root.appending(path: path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(origin: .zero, size: size)
    NSGradient(colors: [
        NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1),
        NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.55, alpha: 1),
    ])!.draw(in: rect, angle: -35)
    NSColor(white: 1, alpha: 0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: size.width * 0.58, y: size.height * 0.55, width: size.height * 0.28, height: size.height * 0.28)).fill()
    NSColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.35, brightness: 0.25, alpha: 0.9).setFill()
    let hills = NSBezierPath()
    hills.move(to: .zero)
    hills.line(to: NSPoint(x: 0, y: size.height * 0.35))
    hills.curve(to: NSPoint(x: size.width, y: size.height * 0.28), controlPoint1: NSPoint(x: size.width * 0.3, y: size.height * 0.62), controlPoint2: NSPoint(x: size.width * 0.6, y: size.height * 0.05))
    hills.line(to: NSPoint(x: size.width, y: 0))
    hills.fill()
    NSGraphicsContext.restoreGraphicsState()
    let type: NSBitmapImageRep.FileType = url.pathExtension == "png" ? .png : .jpeg
    try? rep.representation(using: type, properties: [.compressionFactor: 0.92])?.write(to: url)
    touch(url, daysAgo: daysAgo)
}

@discardableResult
func git(_ arguments: [String], in root: URL, daysAgo: Double = 0) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-c", "user.name=Alex Doe", "-c", "user.email=alex@example.com", "-c", "commit.gpgsign=false"] + arguments
    process.currentDirectoryURL = root
    let stamp = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -daysAgo * 86_400))
    process.environment = ProcessInfo.processInfo.environment.merging(["GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp]) { $1 }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

let project = base.appending(path: "aurora-web")
let readme = """
<p align="center"><img src="docs/logo.png" width="96"></p>

# Aurora Web

The marketing site and customer dashboard for **Aurora**, built with Next.js and a small Go API.

## Features

- Server-rendered landing pages with image optimisation
- Customer dashboard with usage charts and invoices
- A tiny Go API for auth, billing webhooks and email
- One-command local setup with Docker

## Getting started

```bash
git clone git@github.com:acme/aurora-web.git
cd aurora-web
npm install && npm run dev
```

Open `http://localhost:3000` and sign in with the demo account.

## Project layout

| Folder | What lives there |
|--------|------------------|
| `src/` | Next.js app and components |
| `api/` | Go API service |
| `public/` | Images, fonts and videos |
| `docs/` | Architecture notes |

> Deploys run on every merge to `main`.

## License

MIT
"""
write("README.md", readme, in: project, daysAgo: 12)
write("package.json", #"{"name":"aurora-web","private":true,"scripts":{"dev":"next dev","build":"next build"}}"#, in: project, daysAgo: 30)
write(".gitignore", "node_modules/\n.next/\n", in: project, daysAgo: 60)
let components = ["Header", "Footer", "Hero", "PricingTable", "UsageChart", "InvoiceList", "SignInForm", "Sidebar", "Avatar", "Button", "Modal", "Toast"]
for (index, name) in components.enumerated() {
    write("src/components/\(name).tsx", "export function \(name)() {\n  return <div className=\"\(name.lowercased())\" />\n}\n" + String(repeating: "// layout\n", count: 40 * (index + 1)), in: project, daysAgo: Double(index * 3 + 2))
}
for page in ["index", "pricing", "dashboard", "settings", "invoices", "blog"] {
    write("src/pages/\(page).tsx", "export default function Page() { return null }\n" + String(repeating: "const row = 1\n", count: 300), in: project, daysAgo: 9)
}
for file in ["main.go", "auth.go", "billing.go", "email.go", "router.go"] {
    write("api/\(file)", "package main\n" + String(repeating: "func handler() {}\n", count: 220), in: project, daysAgo: 20)
}
write("docs/architecture.md", "# Architecture\n\nNotes.", in: project, daysAgo: 40)
write("docs/deploy.md", "# Deploy\n\nNotes.", in: project, daysAgo: 40)
image("public/images/hero.jpg", hue: 0.58, in: project, size: CGSize(width: 2400, height: 1350), daysAgo: 15)
image("public/images/dashboard.png", hue: 0.66, in: project, size: CGSize(width: 1800, height: 1200), daysAgo: 15)
image("docs/logo.png", hue: 0.05, in: project, size: CGSize(width: 512, height: 512), daysAgo: 40)
blob("public/videos/product-tour.mp4", megabytes: 24, in: project, daysAgo: 18)
blob("public/fonts/Inter.woff2", megabytes: 0.3, in: project, daysAgo: 50)
blob("design/brand-kit.zip", megabytes: 7.5, in: project, daysAgo: 25)

git(["init", "-q", "-b", "main"], in: project, daysAgo: 60)
git(["remote", "add", "origin", "git@github.com:acme/aurora-web.git"], in: project)
git(["add", "."], in: project)
git(["commit", "-q", "-m", "Initial import"], in: project, daysAgo: 60)
write("src/components/PricingTable.tsx", "export function PricingTable() {\n  return <table />\n}\n" + String(repeating: "// tiers\n", count: 90), in: project, daysAgo: 1)
git(["commit", "-q", "-am", "Add annual billing toggle to the pricing table"], in: project, daysAgo: 1)
git(["checkout", "-q", "-b", "feature/usage-alerts"], in: project)
write("src/components/UsageChart.tsx", "export function UsageChart() {\n  return <svg />\n}\n// alert threshold line\n", in: project)
write("api/billing.go", "package main\n// webhook retries\n", in: project)

let photos = base.appending(path: "Product Photos")
let shots = ["studio-01", "studio-02", "studio-03", "lifestyle-01", "lifestyle-02", "lifestyle-03", "detail-01", "detail-02", "detail-03", "detail-04", "flatlay-01", "flatlay-02", "packaging-01", "packaging-02", "banner-wide", "banner-square"]
for (index, name) in shots.enumerated() {
    image("\(name).jpg", hue: CGFloat(index) / CGFloat(shots.count), in: photos, daysAgo: Double(index))
}
write("shot-list.txt", "Spring catalogue shoot\n", in: photos, daysAgo: 20)

let archive = base.appending(path: "Client Handoff")
for folder in ["Contracts", "Invoices", "Designs", "Exports", "Photos", "Video"] {
    for index in 1...30 {
        write("\(folder)/\(folder.lowercased())-\(index).txt", String(repeating: "x", count: 2_000 * index), in: archive, daysAgo: Double(index))
    }
}
blob("Video/final-cut-4k.mov", megabytes: 120, in: archive, daysAgo: 3)
blob("Video/teaser.mp4", megabytes: 35, in: archive, daysAgo: 5)
blob("Exports/print-ready.pdf", megabytes: 18, in: archive, daysAgo: 7)
image("Photos/cover.jpg", hue: 0.3, in: archive, daysAgo: 2)

print("Demo data in \(base.path)")
