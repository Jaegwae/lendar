// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaverCalDAVViewer",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NaverCalDAVViewer",
            dependencies: []
        )
    ]
)
