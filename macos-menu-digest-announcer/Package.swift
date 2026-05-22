// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DigestAnnouncer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DigestAnnouncer",
            path: "Sources/DigestAnnouncer"
        )
    ]
)
