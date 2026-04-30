// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubtitleCover",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SubtitleCover", targets: ["SubtitleCover"]),
        .executable(name: "SubtitleCoverWindows", targets: ["SubtitleCoverWindows"]),
        .executable(name: "SubtitleCoverLauncher", targets: ["SubtitleCoverLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "SubtitleCover",
            path: "Sources/SubtitleCover"
        ),
        .executableTarget(
            name: "SubtitleCoverWindows",
            path: "Sources/SubtitleCoverWindows"
        ),
        .executableTarget(
            name: "SubtitleCoverLauncher",
            path: "Sources/SubtitleCoverLauncher"
        )
    ]
)
