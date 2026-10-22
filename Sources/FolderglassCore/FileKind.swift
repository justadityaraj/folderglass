import Foundation
import UniformTypeIdentifiers

public enum FileKind: String, CaseIterable, Sendable {
    case image, video, audio, code, document, archive, other

    public var title: String {
        switch self {
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .code: "Code"
        case .document: "Documents"
        case .archive: "Archives"
        case .other: "Other"
        }
    }

    private static let codeExtensions: Set<String> = [
        "c", "cc", "cpp", "cs", "css", "dart", "ex", "exs", "go", "gradle", "h", "hpp", "html", "java", "js", "json",
        "jsx", "kt", "kts", "lua", "m", "mm", "php", "pl", "py", "rb", "rs", "sass", "scala", "scss", "sh", "sql",
        "svelte", "swift", "toml", "ts", "tsx", "vue", "xml", "yaml", "yml", "zsh", "fish", "mjs", "cjs", "lock",
    ]

    private static let documentExtensions: Set<String> = [
        "md", "markdown", "txt", "rtf", "pdf", "doc", "docx", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx",
        "csv", "tsv", "epub", "odt",
    ]

    public init(fileExtension: String) {
        let ext = fileExtension.lowercased()
        if Self.codeExtensions.contains(ext) { self = .code; return }
        if Self.documentExtensions.contains(ext) { self = .document; return }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { self = .other; return }
        if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .sourceCode) || type.conforms(to: .script) { self = .code }
        else if type.conforms(to: .archive) || type.conforms(to: .diskImage) { self = .archive }
        else if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) { self = .document }
        else { self = .other }
    }
}
