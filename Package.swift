// swift-tools-version:5.10
import PackageDescription

// Zero third-party dependencies by design (docs/QUALITY_GATE.md): no Package.resolved is needed.
let package = Package(
    name: "PixelCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PixelCompanion", targets: ["PixelCompanion"])
    ],
    targets: [
        // Platform-neutral domain logic: connector protocols, MockConnector, character state
        // machine, settings and notch geometry. Foundation (+ CoreGraphics where available), no AppKit,
        // so it remains headless-testable.
        .target(name: "PixelCompanionCore"),
        // The macOS app: AppKit + SwiftUI shell over PixelCompanionCore. No Info.plist or entitlements.
        .executableTarget(name: "PixelCompanion", dependencies: ["PixelCompanionCore"]),
        .testTarget(name: "PixelCompanionCoreTests", dependencies: ["PixelCompanionCore"])
    ]
)
