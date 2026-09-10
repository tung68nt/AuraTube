// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuraTube",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AuraTube",
            targets: ["AuraTube"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AuraTube",
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
