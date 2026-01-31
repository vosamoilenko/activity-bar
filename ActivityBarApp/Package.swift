// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActivityBarApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ActivityBarApp", targets: ["App"])
    ],
    targets: [
        // Main app target
        .executableTarget(
            name: "App",
            dependencies: ["Core", "Providers", "Storage"],
            path: "Sources/App"
        ),
        // Core module: shared types, state management
        .target(
            name: "Core",
            path: "Sources/Core"
        ),
        // Providers module: API adapters informed by activity-discovery
        .target(
            name: "Providers",
            dependencies: ["Core", "Storage"],
            path: "Sources/Providers"
        ),
        // Storage module: cache, keychain, persistence
        .target(
            name: "Storage",
            dependencies: ["Core"],
            path: "Sources/Storage"
        ),
        // Tests
        .testTarget(
            name: "AppTests",
            dependencies: ["App", "Core"],
            path: "Tests/AppTests"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage"],
            path: "Tests/StorageTests"
        ),
        .testTarget(
            name: "ProvidersTests",
            dependencies: ["Providers", "Core"],
            path: "Tests/ProvidersTests"
        )
    ]
)
