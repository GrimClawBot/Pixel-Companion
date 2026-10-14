import AppKit
import Foundation
import PixelCompanionCore
import SwiftUI
@testable import PixelCompanion
import XCTest

/// PC-085 Phase 0 fixture-only reference harness. Renders production header and compact
/// views with synthetic `noConnector` data; writes PNGs only when PIXEL_DESIGN_REFERENCE_DIR is set.
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

    func testReferenceLayoutsRenderDeterministically() throws {
        let snapshot = ConnectorSnapshot.noConnector
        let syncDate = MockScript.referenceDate
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
                                    feedFreshness: state, lastSuccessfulSync: syncDate
                                )
                            }
                            .padding(16)
                            .frame(width: width, alignment: .leading)
                            .dynamicTypeSize(size)
                            let name = [
                                "w\(Int(width))", scheme == .dark ? "dark" : "light",
                                size == .large ? "std" : "ax3", freshnessName, mood.rawValue
                            ].joined(separator: "-")
                            let png = try render(content, width: width, scheme: scheme)
                            XCTAssertFalse(png.isEmpty, name)
                            try saveOptional(png, name: name)
                        }
                    }
                }
            }
        }
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
