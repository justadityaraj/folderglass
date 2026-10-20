import AppKit
import FoldoutUI
import Quartz
import SwiftUI

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var model: PreviewModel?

    override func loadView() {
        view = NSView()
        preferredContentSize = NSSize(width: 820, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = PreviewModel(url: url, content: PreviewModel.content(for: url))
        self.model = model
        let host = NSHostingView(rootView: PreviewView(model: model))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        model.start()
        recordIfVerifying(model)
    }

    private func recordIfVerifying(_ model: PreviewModel) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        guard FileManager.default.fileExists(atPath: directory.appending(path: "verify").path) else { return }
        Task { @MainActor in
            await model.load()
            let line = [
                model.url.lastPathComponent,
                "files=\(model.summary?.fileCount ?? -1)",
                "size=\(model.summary?.totalSize ?? -1)",
                "branch=\(model.git?.branch ?? "-")",
                "commit=\(model.git?.lastCommit?.subject ?? "-")",
                "status=\(model.git?.status.map { "\($0.modified)m\($0.deleted)d" } ?? "-")",
                "readme=\(model.readme.count)",
            ].joined(separator: " ") + "\n"
            let log = directory.appending(path: "verify.log")
            if let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: log)
            }
        }
    }

    deinit {
        let model = model
        Task { @MainActor in model?.cancel() }
    }
}
