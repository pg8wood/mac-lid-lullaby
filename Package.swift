// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacBookLidByeBye",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacBookLidByeBye", targets: ["MacBookLidByeBye"])
    ],
    targets: [
        .executableTarget(
            name: "MacBookLidByeBye",
            path: "Sources"
        )
    ]
)
