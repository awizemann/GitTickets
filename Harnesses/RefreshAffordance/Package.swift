// swift-tools-version: 6.0
import PackageDescription

// Deliberately a SEPARATE package from the root one: these are developer tools,
// not shipped code, and nothing here should ever reach an adopter. The root
// package does not reference this directory.
let package = Package(
    name: "RefreshAffordance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // Three-way control: ScrollView plain / ScrollView + .refreshable /
        // List + .refreshable. Uses no SDK code, so it isolates the SwiftUI
        // behavior from anything GitTickets does.
        .executableTarget(name: "ReproHarness"),
        // Hosts the REAL shipped views so findings rest on SDK code.
        .executableTarget(
            name: "SDKHarness",
            dependencies: [.product(name: "GitTickets", package: "GitTickets")]
        ),
    ]
)
