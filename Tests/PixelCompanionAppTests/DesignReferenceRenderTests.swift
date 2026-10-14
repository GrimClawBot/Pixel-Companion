import AppKit
import Foundation
import PixelCompanionCore
import SwiftUI
@testable import PixelCompanion
import XCTest

/// PC-085 Phase 0 fixture-only reference harness. Renders production header and compact
/// views with synthetic `noConnector` data; writes PNGs only when PIXEL_DESIGN_REFERENCE_DIR is set.
/// The PNGs are review references, not approved golden images: nothing here compares pixels.
/// `lastSuccessfulSync` is nil so the header never shows the wall-clock-relative "Last synced"
/// label; that label needs its own time-controlled QA (see docs/PC085_PHASE0_QA_MATRIX.md).
@MainActor
final class DesignReferenceRenderTests: XCTestCase {
    private let widths: [CGFloat] = [360, 440]
    private let schemes: [ColorScheme] = [.light, .dark]
    private let sizes: [DynamicTypeSize] = [.large, .accessibility3]
    private let freshness: [(String, FeedFreshness)] = [
        ("none", .notApplicable), ("connecting", .connecting), ("current", .current),
        ("stale", .stale), ("unavailable", .unavailable)
    ]
    private let moods: [CharacterMood] = [.idle, .working, .waitingForApproval, .error, .offline]

    func testReferenceMatrixCoversEveryFreshnessStateWithUniqueNames() {
        // Exhaustive switch: adding a FeedFreshness case stops this compiling until it is listed above.
        func covered(_ state: FeedFreshness) -> Bool {
            switch state {
            case .notApplicable, .connecting, .current, .stale, .unavailable:
                return freshness.contains { $0.1 == state }
            }
        }
        for state in [FeedFreshness.notApplicable, .connecting, .current, .stale, .unavailable] {
            XCTAssertTrue(covered(state), "\(state)")
        }
        let names = referenceNames()
        XCTAssertEqual(names.count, 200)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testReferenceLayoutsRenderWithoutWallClockText() throws {
        let snapshot = ConnectorSnapshot.noConnector
        for width in widths {
            for scheme in schemes {
                for size in sizes {
                    for (freshnessName, state) in freshness {
                        for mood in moods {
                            let content = VStack(alignment: .leading, spacing: 12) {
                                CompactBar(
                                    snapshot: snapshot, mood: mood,
                                    feedFreshness: state, showsStatusText: true
                                )
                                .padding(8)
                                .background(Color.black)
                                SummaryHeader(
                                    snapshot: snapshot, mood: mood,
                                    feedFreshness: state, lastSuccessfulSync: nil
                                )
                            }
                            .padding(16)
                            .frame(width: width, alignment: .leading)
                            .dynamicTypeSize(size)
                            let name = referenceName(width, scheme, size, freshnessName, mood)
                            let png = try render(content, width: width, scheme: scheme)
                            XCTAssertFalse(png.isEmpty, name)
                            try saveOptional(png, name: name)
                        }
                    }
                }
            }
        }
    }

    private func referenceNames() -> [String] {
        widths.flatMap { width in
            schemes.flatMap { scheme in
                sizes.flatMap { size in
                    freshness.flatMap { entry in
                        moods.map { referenceName(width, scheme, size, entry.0, $0) }
                    }
                }
            }
        }
    }

    private func referenceName(
        _ width: CGFloat, _ scheme: ColorScheme, _ size: DynamicTypeSize,
        _ freshnessName: String, _ mood: CharacterMood
    ) -> String {
        [
            "w\(Int(width))", scheme == .dark ? "dark" : "light",
            size == .large ? "std" : "ax3", freshnessName, mood.rawValue
        ].joined(separator: "-")
    }

    private func render(_ view: some View, width: CGFloat, scheme: ColorScheme) throws -> Data {
        let content = view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let height = max(host.fittingSize.height, 1)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        host.frame = rect
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else {
            throw NSError(domain: "PC085Reference", code: 1)
        }
        host.cacheDisplay(in: rect, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PC085Reference", code: 2)
        }
        return data
    }

    private func saveOptional(_ png: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PIXEL_DESIGN_REFERENCE_DIR"] else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }
}
