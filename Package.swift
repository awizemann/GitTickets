// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GitTickets",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
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
                // Snapshot test baseline directory. The PNGs are NOT checked in
                // (their contents are gitignored) and SnapshotTests skips itself
                // when `CI` is set — see that file for why. This exclude keeps
                // SPM from treating the images a *local* run records as unhandled
                // resources. The directory is kept alive in git by a committed
                // `.gitkeep`, because SPM warns "Invalid Exclude … File not
                // found" whenever an excluded path is missing — which on a clean
                // checkout (i.e. every CI run) it otherwise would be.
                "UI/SwiftUI/__Snapshots__",
            ]
        ),
    ],
    // Compile every target under the Swift 6 language mode so this dependency
    // stays Swift-6-clean for adopters (e.g. Memophant) moving to Swift 6.
    swiftLanguageModes: [.v6]
)
