// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MikkelPet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PetCore",
            path: "Sources/PetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MikkelPetTests",
            dependencies: ["PetCore"],
            path: "Tests/MikkelPetTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MikkelPet",
            dependencies: ["PetCore"],
            path: "Sources/MikkelPet",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "mikkel-hook",
            path: "Sources/mikkel-hook",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
