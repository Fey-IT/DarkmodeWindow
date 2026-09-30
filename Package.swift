// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DarkmodeWindow",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DarkmodeWindow",
            path: "Sources/DarkmodeWindow",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
