// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResearchAtlas",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ResearchAtlas",
            path: "Sources/ResearchAtlas",
            exclude: ["Info.plist"],
            // Embed an Info.plist into the executable so ATS (App Transport
            // Security) honors the cleartext-HTTP exception needed to reach the
            // backend over Tailscale (plain HTTP, non-loopback IP).
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ResearchAtlas/Info.plist",
                ])
            ]
        )
    ]
)
