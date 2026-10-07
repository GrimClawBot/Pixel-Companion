import PixelCompanionCore
import XCTest

final class CharacterStateMachineTests: XCTestCase {
    private let date = MockScript.referenceDate

    private func snapshot(
        _ state: ConnectionState = .connected,
        activity: ActivityEvent.Kind? = nil,
        approvals: Int = 0
    ) -> ConnectorSnapshot {
        ConnectorSnapshot(
            connectorName: "Test",
            connectionState: state,
            currentActivity: activity.map { ActivityEvent(id: "a", kind: $0, title: "Activity", timestamp: date) },
            pendingApprovals: (0..<approvals).map { ApprovalRequest(id: "r\($0)", title: "Approve", requestedAt: date) }
        )
    }

    func testMoodPrecedence() {
        let busy = snapshot(.disconnected, activity: .running, approvals: 1)
        XCTAssertEqual(CharacterStateMachine.mood(for: busy), .offline)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(.connecting, activity: .running)), .offline)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(.error, activity: .running, approvals: 1)), .error)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(activity: .failed, approvals: 1)), .waitingForApproval)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(activity: .failed)), .error)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(activity: .running)), .working)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(activity: .completed)), .idle)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot(activity: .note)), .idle)
        XCTAssertEqual(CharacterStateMachine.mood(for: snapshot()), .idle)
    }

    func testNoConnectorIsOffline() {
        XCTAssertEqual(CharacterStateMachine.mood(for: .noConnector), .offline)
    }

    func testUpdateRecordsTransitionsAndIgnoresRepeats() {
        var machine = CharacterStateMachine()
        XCTAssertEqual(machine.mood, .offline)

        let first = machine.update(with: snapshot(activity: .running))
        XCTAssertEqual(first, CharacterTransition(previous: .offline, current: .working))
        XCTAssertNil(machine.update(with: snapshot(activity: .running)))
        XCTAssertEqual(machine.transitionCount, 1)

        machine.update(with: snapshot(.disconnected))
        XCTAssertEqual(machine.mood, .offline)
        XCTAssertEqual(machine.lastTransition, CharacterTransition(previous: .working, current: .offline))
        XCTAssertEqual(machine.transitionCount, 2)
    }

    func testDemoScriptDrivesEveryMood() {
        let connector = MockConnector(id: .mockDemo, displayName: "Mock", script: .demo)
        var machine = CharacterStateMachine()
        var moods: [CharacterMood] = []
        for _ in MockScript.demo.steps {
            machine.update(with: ConnectorSnapshot(capturing: connector))
            moods.append(machine.mood)
            connector.refresh()
        }

        XCTAssertEqual(moods, [.idle, .working, .working, .waitingForApproval, .working, .error, .working, .idle])
    }

    func testSimulatedConnectionStatesDriveOfflineAndError() {
        let connector = MockConnector(id: .mockDemo, displayName: "Mock", script: .demo)
        var machine = CharacterStateMachine(initialMood: .idle)
        let expected: [ConnectionState: CharacterMood] = [
            .connected: .idle, .connecting: .offline, .disconnected: .offline, .error: .error
        ]

        for state in ConnectionState.allCases {
            connector.simulatedConnectionState = state
            machine.update(with: ConnectorSnapshot(capturing: connector))
            XCTAssertEqual(machine.mood, expected[state], "\(state)")
        }
    }

    func testEveryMoodHasPresentationMetadata() {
        for mood in CharacterMood.allCases {
            XCTAssertFalse(mood.title.isEmpty)
            XCTAssertFalse(mood.symbolName.isEmpty)
        }
    }

    func testEveryMoodHasWellFormedAnimationFrames() {
        for mood in CharacterMood.allCases {
            let frames = CharacterSprite.frames(for: mood)
            XCTAssertGreaterThanOrEqual(frames.count, 2, "\(mood) needs an animation")
            for frame in frames {
                XCTAssertEqual(frame.pixels.count, CharacterSprite.height, "\(mood)")
                XCTAssertTrue(frame.pixels.allSatisfy { $0.count == CharacterSprite.width }, "\(mood)")
                XCTAssertTrue(frame.pixels.joined().contains(.eye), "\(mood) needs a face")
            }
        }
    }

    func testSpriteParsingTreatsUnknownCharactersAsTransparent() {
        let sprite = CharacterSprite(rows: ["BHEMA.x"])

        XCTAssertEqual(sprite.pixels, [[.body, .highlight, .eye, .mouth, .accent, nil, nil]])
    }
}
