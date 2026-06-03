// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SteadyIntentions",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SteadyIntentions",
            path: "Sources/SteadyIntentions"
        )
    ]
)
