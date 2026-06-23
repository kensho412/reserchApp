// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResearchAtlas",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ResearchAtlas",
            path: "Sources/ResearchAtlas"
        )
    ]
)
