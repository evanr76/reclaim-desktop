// swift-tools-version: 5.9
import PackageDescription

// Shared networking/model layer (`ReclaimKit`) plus a command-line probe for
// testing the Reclaim API with a live key, independent of the SwiftUI app.
//
// The macOS app (ReclaimDesktop.xcodeproj) compiles the same source files under
// ReclaimDesktop/Models and ReclaimDesktop/Services directly, so the probe
// exercises the exact code the app runs.
let package = Package(
    name: "ReclaimKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ReclaimKit", targets: ["ReclaimKit"]),
        .executable(name: "reclaim-probe", targets: ["reclaim-probe"]),
    ],
    targets: [
        .target(
            name: "ReclaimKit",
            path: "ReclaimDesktop",
            // App-only files live in the same folder tree but belong to the
            // Xcode app target, not this shared library.
            exclude: [
                "ReclaimDesktopApp.swift",
                "ReclaimDesktop.entitlements",
                "Views",
                "ViewModels",
                "AppIntents",
                "Assets.xcassets",
                "Services/KeychainStore.swift",
                "Services/LoginItem.swift",
            ],
            sources: [
                "Models/Enums.swift",
                "Models/ReclaimTask.swift",
                "Models/User.swift",
                "Models/Moment.swift",
                "Models/BuildInfo.swift",
                "Services/ReclaimAPIClient.swift",
            ]
        ),
        .executableTarget(
            name: "reclaim-probe",
            dependencies: ["ReclaimKit"],
            path: "Sources/reclaim-probe"
        ),
    ]
)
