// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Workstate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WorkstateCore", targets: ["WorkstateCore"]),
        .library(name: "WorkstateIngestion", targets: ["WorkstateIngestion"]),
        .library(name: "WorkstateUI", targets: ["WorkstateUI"]),
        .executable(name: "Workstate", targets: ["WorkstateApp"]),
        .executable(name: "WorkstateCLI", targets: ["WorkstateCLI"]),
        .executable(name: "WorkstatePreview", targets: ["WorkstatePreview"]),
        .executable(name: "WorkstateChecks", targets: ["WorkstateChecks"]),
        .executable(name: "WorkstateSnapshot", targets: ["WorkstateSnapshot"]),
        .executable(name: "WorkstateDaemon", targets: ["WorkstateDaemon"]),
        .executable(name: "WorkstateRebuild", targets: ["WorkstateRebuild"]),
        .executable(name: "WorkstateMigrateV4", targets: ["WorkstateMigrateV4"])
    ],
    targets: [
        .target(name: "WorkstateCore"),
        .target(
            name: "WorkstateIngestion",
            dependencies: ["WorkstateCore"]
        ),
        .target(
            name: "WorkstateUI",
            dependencies: ["WorkstateCore", "WorkstateIngestion"]
        ),
        .executableTarget(
            name: "WorkstateApp",
            dependencies: ["WorkstateCore", "WorkstateUI"]
        ),
        .executableTarget(
            name: "WorkstateCLI",
            dependencies: ["WorkstateCore", "WorkstateIngestion"]
        ),
        .executableTarget(
            name: "WorkstatePreview",
            dependencies: ["WorkstateCore", "WorkstateUI"]
        ),
        .executableTarget(
            name: "WorkstateChecks",
            dependencies: ["WorkstateCore", "WorkstateUI", "WorkstateIngestion"]
        ),
        .executableTarget(
            name: "WorkstateSnapshot",
            dependencies: ["WorkstateCore", "WorkstateUI"]
        ),
        .executableTarget(
            name: "WorkstateDaemon",
            dependencies: ["WorkstateCore", "WorkstateIngestion"]
        ),
        .executableTarget(
            name: "WorkstateRebuild",
            dependencies: ["WorkstateCore", "WorkstateIngestion"]
        ),
        .executableTarget(
            name: "WorkstateMigrateV4",
            dependencies: ["WorkstateCore", "WorkstateIngestion"]
        )
    ]
)
