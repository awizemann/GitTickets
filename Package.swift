// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GitTickets",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "GitTickets", targets: ["GitTickets"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "GitTickets",
            dependencies: [],
            resources: [
                // Privacy manifest required by Apple for SDKs distributed via SPM.
                // Declared here so the file is copied into the SDK's resource
                // bundle and inherits the adopter's app for App Store review.
                .copy("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "GitTicketsTests",
            dependencies: [
                "GitTickets",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: [
                // Snapshot test baselines — checked in next to their tests
                // but not Swift sources, so SPM warns unless we exclude them.
                "UI/SwiftUI/__Snapshots__",
            ]
        ),
    ],
    // Compile every target under the Swift 6 language mode so this dependency
    // stays Swift-6-clean for adopters (e.g. Memophant) moving to Swift 6.
    swiftLanguageModes: [.v6]
)
