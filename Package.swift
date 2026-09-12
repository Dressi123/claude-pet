// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PetCore",
            path: "Sources/PetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudePetTests",
            dependencies: ["PetCore"],
            path: "Tests/ClaudePetTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudePet",
            dependencies: ["PetCore"],
            path: "Sources/ClaudePet",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "claude-pet-hook",
            path: "Sources/claude-pet-hook",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
