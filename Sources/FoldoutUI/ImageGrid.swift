import AppKit
import FoldoutCore
import ImageIO
import SwiftUI

struct ImageGrid: View {
    let root: URL
    let items: [FileItem]
    let total: Int

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 5) {
                        Thumbnail(url: root.appending(path: item.path), fallback: Format.icon(for: item))
                            .frame(height: 110)
                        Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
                        Text(Format.bytes(item.size)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
            if total > items.count {
                Text("Showing \(items.count) of \(total.formatted()) images").font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    let fallback: NSImage
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            } else {
                Image(nsImage: fallback).resizable().aspectRatio(contentMode: .fit).padding(24).opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = await Task.detached(priority: .utility) { Self.load(url) }.value
        }
    }

    nonisolated static func load(_ url: URL) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
