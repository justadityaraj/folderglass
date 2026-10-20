// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foldout",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FoldoutCore"),
        .target(name: "FoldoutUI", dependencies: ["FoldoutCore"]),
        .executableTarget(name: "Foldout", dependencies: ["FoldoutUI"]),
        .executableTarget(
            name: "FoldoutPreview",
            dependencies: ["FoldoutUI"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .executableTarget(name: "FoldoutSelfCheck", dependencies: ["FoldoutCore"]),
        .executableTarget(name: "FoldoutSnapshots", dependencies: ["FoldoutUI"]),
    ],
    swiftLanguageModes: [.v5]
)
