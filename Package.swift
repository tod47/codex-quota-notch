// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaNotch",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexQuotaNotch", targets: ["CodexQuotaNotch"])
    ],
    targets: [
        .executableTarget(
            name: "CodexQuotaNotch",
            path: "Sources/CodexQuotaNotch",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CodexQuotaNotchTests",
            dependencies: ["CodexQuotaNotch"],
            path: "Tests/CodexQuotaNotchTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
