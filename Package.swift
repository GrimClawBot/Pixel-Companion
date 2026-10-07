// swift-tools-version:5.10
import PackageDescription

// Zero third-party dependencies by design (docs/QUALITY_GATE.md): no Package.resolved is needed.
let package = Package(
    name: "PixelCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-neutral domain logic: connector protocols, MockConnector, character state
        // machine, settings and notch geometry. Foundation only, so it also builds and tests on Linux.
        .target(name: "PixelCompanionCore"),
        .testTarget(name: "PixelCompanionCoreTests", dependencies: ["PixelCompanionCore"])
    ]
)
