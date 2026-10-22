// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folderglass",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FolderglassCore"),
        .target(name: "FolderglassUI", dependencies: ["FolderglassCore"]),
        .executableTarget(name: "Folderglass", dependencies: ["FolderglassCore", "FolderglassUI"]),
        .executableTarget(
            name: "FolderglassPreview",
            dependencies: ["FolderglassUI"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .executableTarget(name: "FolderglassSelfCheck", dependencies: ["FolderglassCore"]),
        .executableTarget(name: "FolderglassSnapshots", dependencies: ["FolderglassUI"]),
    ],
    swiftLanguageModes: [.v5]
)
