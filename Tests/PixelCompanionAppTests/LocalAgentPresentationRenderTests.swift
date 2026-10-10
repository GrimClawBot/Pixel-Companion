import AppKit
import Foundation
import PixelCompanionCore
import SwiftUI
@testable import PixelCompanion
import XCTest

/// Renders the PRODUCTION tab views at both real surface sizes with strictly
/// synthetic marker data. Does not screen-record or inspect private desktop.
@MainActor
final class LocalAgentPresentationRenderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC51Visual-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: false
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func monitors() async -> (CodexTurnMonitor, ClaudeHookMonitor) {
        let now = Date()
        let date = ISO8601DateFormatter().string(from: now)
        let codexData = Data(
            """
            {"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"\(date)"}
            """.utf8
        )
        let claudeData = Data(
            """
            {"schemaVersion":1,"event":"Stop","observedAt":"\(date)"}
            """.utf8
        )
        let codex = CodexTurnMonitor(read: { _ in codexData })
        let claude = ClaudeHookMonitor(read: { _ in claudeData })
        codex.configure(enabled: true)
        claude.configure(enabled: true)
        codex.connectDirectory(tempDirectory)
        claude.connectDirectory(tempDirectory)
        await waitForMonitorStatus {
            if case .observed = codex.status, case .observed = claude.status { return true }
            return false
        }
        return (codex, claude)
    }

    func testNativeAgentCardsRenderAtBothSurfaceWidths() async throws {
        let (codex, claude) = await monitors()
        defer {
            codex.configure(enabled: false)
            claude.configure(enabled: false)
        }
        for width in [360, 440] {
            for scheme in [ColorScheme.dark, .light] {
                let view = DetailContent(
                    snapshot: .noConnector, mood: .offline, openSettings: {},
                    codexTurnMonitor: codex, claudeHookMonitor: claude,
                    selectedTab: .constant(.agents)
                )
                let bytes = try render(view, width: width, height: 440, scheme: scheme)
                XCTAssertGreaterThan(bytes.count, 4_000)
                try saveOptional(bytes, name: "agents-\(width)-\(scheme).png")
            }
        }
    }

    func testNativeActivityCardRendersWithoutPaperclipData() async throws {
        let (codex, claude) = await monitors()
        defer {
            codex.configure(enabled: false)
            claude.configure(enabled: false)
        }
        let timeline = LocalAgentActivityTimeline()
        timeline.bind(codex: codex, claude: claude)
        XCTAssertEqual(timeline.events.count, 2)
        for width in [360, 440] {
            for scheme in [ColorScheme.dark, .light] {
                let view = DetailContent(
                    snapshot: .noConnector, mood: .offline, openSettings: {},
                    codexTurnMonitor: codex, claudeHookMonitor: claude,
                    localActivityTimeline: timeline, selectedTab: .constant(.activity)
                )
                let bytes = try render(view, width: width, height: 440, scheme: scheme)
                XCTAssertGreaterThan(bytes.count, 4_000)
                try saveOptional(bytes, name: "activity-\(width)-\(scheme).png")
            }
        }
    }

    private func render<V: View>(
        _ view: V, width: Int, height: Int, scheme: ColorScheme
    ) throws -> Data {
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let content = view
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = rect
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else {
            throw NSError(domain: "PC51Visual", code: 1)
        }
        host.cacheDisplay(in: rect, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PC51Visual", code: 2)
        }
        return data
    }

    private func saveOptional(_ png: Data, name: String) throws {
        guard let capture = ProcessInfo.processInfo.environment["PIXEL_QA_CAPTURE_DIR"] else {
            return
        }
        let folder = URL(fileURLWithPath: capture, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        try png.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
