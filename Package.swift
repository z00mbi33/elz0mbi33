// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "elz0mbi33",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "elz0mbi33", targets: ["elz0mbi33"])
    ],
    targets: [
        .executableTarget(
            name: "elz0mbi33",
            path: "Sources/FloatingLyrics"
        )
    ]
)
