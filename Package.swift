// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipboardy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clipboardy",
            path: "Sources"
        )
    ]
)
