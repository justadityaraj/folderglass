import Foundation

public extension Bundle {
    static let folderglass = Bundle.module
}

public func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .folderglass)
}
