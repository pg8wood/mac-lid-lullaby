// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mac-lid-lullaby",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "mac-lid-lullaby", targets: ["MacLidLullaby"])
    ],
    targets: [
        .executableTarget(
            name: "MacLidLullaby",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
