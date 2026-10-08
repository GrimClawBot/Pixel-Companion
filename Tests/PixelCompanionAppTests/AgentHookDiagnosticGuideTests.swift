import Foundation
@testable import PixelCompanion
import XCTest

final class AgentHookDiagnosticGuideTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    func testDisabledSourcesNeverReportReady() {
        let codex = AgentHookDiagnosticGuide.codex(
            status: .off, check: .notStarted, now: reference
        )
        let claude = AgentHookDiagnosticGuide.claude(
            status: .off, check: .notStarted, now: reference
        )
        XCTAssertEqual(codex.stage, .disabled)
        XCTAssertEqual(claude.stage, .disabled)
        XCTAssertTrue(codex.nextStep.contains("Enable"))
    }

    func testEnabledButUnconnectedRequiresFolderSelection() {
        XCTAssertEqual(
            AgentHookDiagnosticGuide.codex(
                status: .unconnected, check: .needsSetup, now: reference
            ).stage, .needsFolder
        )
        XCTAssertEqual(
            AgentHookDiagnosticGuide.claude(
                status: .unconnected, check: .needsSetup, now: reference
            ).stage, .needsFolder
        )
    }

    func testMissingOrInvalidMarkerCannotCountAsHookDelivery() {
        let result = AgentHookDiagnosticGuide.codex(
            status: .unavailable, check: .notStarted, now: reference
        )
        XCTAssertEqual(result.stage, .noValidMarker)
        XCTAssertFalse(result.summary.contains("verified"))
    }

    func testExistingFreshMarkerAloneDoesNotProveProviderOrigin() {
        let result = AgentHookDiagnosticGuide.codex(
            status: .observed(reference), check: .notStarted, now: reference
        )
        XCTAssertEqual(result.stage, .markerAvailable)
        XCTAssertTrue(result.summary.contains("unverified"))
        XCTAssertTrue(result.nextStep.contains("Start check"))
    }

    func testExistingOldMarkerCannotBePresentedAsLive() {
        let old = reference.addingTimeInterval(-121)
        let result = AgentHookDiagnosticGuide.claude(
            status: .observed(event: .responseStopped, timestamp: old),
            check: .notStarted, now: reference
        )
        XCTAssertEqual(result.stage, .oldMarker)
        XCTAssertTrue(result.nextStep.contains("NEW"))
    }

    func testVerificationWaitIsNotMistakenForCompletion() {
        let check = AgentHookCheckState.waiting(reference)
        let result = AgentHookDiagnosticGuide.codex(
            status: .unavailable, check: check, now: reference
        )
        XCTAssertEqual(result.stage, .waitingForNew)
        XCTAssertFalse(result.summary.contains("completed"))
    }

    func testNewMarkerCheckIsCarefulAboutAuthentication() {
        let result = AgentHookDiagnosticGuide.claude(
            status: .observed(event: .promptSubmitted, timestamp: reference),
            check: .observed(reference), now: reference
        )
        XCTAssertEqual(result.stage, .newlyChanged)
        XCTAssertTrue(result.nextStep.contains("NOT authenticated"))
    }

    func testTimedOutCheckOffersExternalConfigTroubleshooting() {
        let result = AgentHookDiagnosticGuide.codex(
            status: .unavailable, check: .timedOut, now: reference
        )
        XCTAssertEqual(result.stage, .timedOut)
        XCTAssertTrue(result.nextStep.contains("external"))
    }

    func testNoPathsPromptsOrCredentialsInExplanations() {
        let results = [
            AgentHookDiagnosticGuide.codex(
                status: .unavailable, check: .notStarted, now: reference
            ),
            AgentHookDiagnosticGuide.claude(
                status: .observed(event: .responseFailed, timestamp: reference),
                check: .notStarted, now: reference
            )
        ]
        let all = results.map { $0.summary + " " + $0.nextStep }.joined()
        for forbidden in ["/Users/", "transcript_path", "session_id", "token", "PRIVATE"] {
            XCTAssertFalse(all.contains(forbidden))
        }
    }
}
