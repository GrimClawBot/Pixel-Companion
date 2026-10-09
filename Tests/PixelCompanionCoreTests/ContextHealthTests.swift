@testable import PixelCompanionCore
import XCTest

final class ContextHealthTests: XCTestCase {
    private func sample(
        _ used: Int?, _ total: Int?, confidence: ContextConfidence = .providerReported,
        compactions: Int? = nil, changed: Bool? = nil, toolOutput: Int? = nil
    ) -> ContextHealth {
        ContextHealth(
            reportedUsed: used, reportedWindow: total, confidence: confidence,
            compactions: compactions, taskChanged: changed,
            recentToolOutputTokens: toolOutput
        )
    }

    func testUnknownNeverGeneratesRecommendationOrInventedZero() {
        for value in [
            sample(nil, nil),
            sample(99, nil),
            sample(nil, 100),
            sample(100, 0),
            sample(-1, 100),
            sample(101, 100),
            sample(88, 100, confidence: .unknown)
        ] {
            XCTAssertNil(value.fraction)
            XCTAssertNil(value.usedTokens)
            XCTAssertEqual(value.confidence, .unknown)
            XCTAssertEqual(value.recommendation, .unavailable)
            XCTAssertTrue(value.reasons.isEmpty)
        }
    }

    func testContextThresholdBoundariesStayConservative() {
        XCTAssertEqual(sample(699, 1_000).recommendation, .healthy)
        XCTAssertEqual(sample(700, 1_000).recommendation, .watch)
        XCTAssertEqual(sample(849, 1_000).recommendation, .watch)
        XCTAssertEqual(sample(850, 1_000).recommendation, .freshSessionRecommended)
        XCTAssertEqual(sample(949, 1_000).recommendation, .freshSessionRecommended)
        XCTAssertEqual(sample(950, 1_000).recommendation, .stronglyFreshSessionRecommended)
        XCTAssertEqual(sample(1_000, 1_000).fraction, 1)
    }

    func testConfidenceNeverAutomaticallyClaimsExactMeasurements() {
        let provider = sample(800, 1_000)
        XCTAssertEqual(provider.confidence, .providerReported)
        XCTAssertEqual(provider.confidence.label, "Provider reported")
        XCTAssertEqual(sample(800, 1_000, confidence: .estimated).confidence, .estimated)
        XCTAssertEqual(sample(800, 1_000, confidence: .exact).confidence, .exact)
        XCTAssertNotEqual(provider.confidence, .exact)
    }

    func testCompactionAndTaskDriftOnlyMatterWhenExplicitlyReported() {
        XCTAssertEqual(sample(650, 1_000).recommendation, .healthy)
        XCTAssertEqual(
            sample(650, 1_000, compactions: 2).recommendation,
            .freshSessionRecommended
        )
        XCTAssertEqual(
            sample(650, 1_000, changed: true).recommendation,
            .freshSessionRecommended
        )
        XCTAssertEqual(sample(650, 1_000, compactions: 1).recommendation, .healthy)
        XCTAssertEqual(sample(650, 1_000, changed: false).recommendation, .healthy)
        XCTAssertEqual(
            sample(980, 1_000, changed: true).recommendation,
            .stronglyFreshSessionRecommended
        )
    }

    func testLargeReportedToolOutputCanElevateRecommendationButNotFakeContext() {
        XCTAssertEqual(sample(700, 1_000).recommendation, .watch)
        XCTAssertEqual(
            sample(700, 1_000, toolOutput: 200).recommendation,
            .freshSessionRecommended
        )
        XCTAssertEqual(sample(700, 1_000, toolOutput: 199).recommendation, .watch)
        XCTAssertEqual(sample(600, 1_000, toolOutput: 300).recommendation, .healthy)
        XCTAssertEqual(sample(nil, nil, toolOutput: 10_000).recommendation, .unavailable)
        XCTAssertEqual(sample(700, 1_000, toolOutput: -100).recommendation, .watch)
    }

    func testReadOnlyNextStepNeverPretendsToCreateOrHandoffAChat() {
        XCTAssertNil(sample(nil, nil).nextStep)
        XCTAssertNil(sample(600, 1_000).nextStep)

        let watch = sample(700, 1_000)
        XCTAssertTrue(watch.nextStep?.contains("Monitor context") == true)
        XCTAssertFalse(watch.nextStep?.contains("new chat") == true)

        let fresh = sample(850, 1_000)
        XCTAssertTrue(fresh.nextStep?.contains("connected runtime") == true)
        XCTAssertTrue(fresh.nextStep?.contains("preserving goals") == true)

        let strong = sample(950, 1_000)
        XCTAssertTrue(strong.nextStep?.contains("soon") == true)
        XCTAssertTrue(strong.nextStep?.contains("connected runtime") == true)
        XCTAssertNotEqual(fresh.nextStep, strong.nextStep)
    }

    func testDerivedReasonsAreGroundedOnlyInMeasuredInputs() {
        let item = sample(710, 1_000, compactions: 2, changed: true, toolOutput: 300)
        XCTAssertEqual(item.recommendation, .freshSessionRecommended)
        XCTAssertEqual(item.reasons.count, 4)
        XCTAssertTrue(item.reasons[0].contains("71%"))
        XCTAssertTrue(item.reasons.contains("Multiple compactions reported"))
        XCTAssertTrue(item.reasons.contains("A change of task was reported"))
        XCTAssertTrue(item.reasons.contains("Large recent tool output reported"))
    }
}
