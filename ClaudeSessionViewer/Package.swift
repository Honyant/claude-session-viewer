// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessionViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClaudeSessionViewer", targets: ["ClaudeSessionViewer"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSessionViewer",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "ClaudeSessionViewer"
        )
    ]
)
