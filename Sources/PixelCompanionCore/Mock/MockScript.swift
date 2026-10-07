import Foundation

/// One frame of scripted connector state.
public struct MockStep: Equatable, Sendable {
    public var kind: ActivityEvent.Kind
    public var title: String
    public var detail: String?
    /// Titles of the approvals pending while this step is current.
    public var pendingApprovals: [String]
    public var usageUsed: Int
    /// Assistant chat line emitted when the step becomes current.
    public var message: String?

    public init(
        kind: ActivityEvent.Kind,
        title: String,
        detail: String? = nil,
        pendingApprovals: [String] = [],
        usageUsed: Int = 0,
        message: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.pendingApprovals = pendingApprovals
        self.usageUsed = usageUsed
        self.message = message
    }
}

/// A looping, deterministic sequence of steps. Timestamps derive from `startDate` and
/// `stepInterval` only, never from the wall clock, so the same script always replays identically.
public struct MockScript: Equatable, Sendable {
    public var steps: [MockStep]
    public var startDate: Date
    public var stepInterval: TimeInterval
    public var usageLimit: Int?

    /// Creates a script; an empty `steps` array is replaced by a single idle note.
    public init(
        steps: [MockStep],
        startDate: Date = MockScript.referenceDate,
        stepInterval: TimeInterval = 60,
        usageLimit: Int? = 1_000
    ) {
        self.steps = steps.isEmpty ? [Self.idleStep] : steps
        self.startDate = startDate
        self.stepInterval = stepInterval
        self.usageLimit = usageLimit
    }

    /// 2026-01-01T00:00:00Z.
    public static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    /// Stands in for an empty script.
    public static let idleStep = MockStep(kind: .note, title: "Idle")

    /// The step for `tick`, looping. `steps` is mutable, so it can be emptied after `init`; an
    /// empty script then plays `idleStep` instead of dividing by zero.
    public func step(at tick: Int) -> MockStep {
        let count = steps.count
        guard count > 0 else { return Self.idleStep }
        return steps[((tick % count) + count) % count]
    }

    public func timestamp(at tick: Int) -> Date {
        startDate.addingTimeInterval(Double(tick) * stepInterval)
    }

    /// A full agent loop: idle → working → waiting for approval → error → recovery.
    public static let demo = MockScript(steps: [
        MockStep(kind: .note, title: "Ready", detail: "Nothing queued", usageUsed: 120),
        MockStep(
            kind: .running,
            title: "Reading the workspace",
            detail: "Indexing 214 files",
            usageUsed: 180,
            message: "Starting on the notch layout task."
        ),
        MockStep(kind: .running, title: "Running unit tests", detail: "38 of 52 passed so far", usageUsed: 260),
        MockStep(
            kind: .running,
            title: "Waiting for review",
            detail: "Change is ready to merge",
            pendingApprovals: ["Merge “Notch layout” change"],
            usageUsed: 300,
            message: "The change is ready. It needs a human approval to continue."
        ),
        MockStep(kind: .running, title: "Applying review feedback", detail: "2 comments", usageUsed: 380),
        MockStep(
            kind: .failed,
            title: "Lint failed",
            detail: "2 violations in NotchView.swift",
            usageUsed: 420,
            message: "Lint failed; fixing it now."
        ),
        MockStep(kind: .running, title: "Fixing lint", detail: "Re-running checks", usageUsed: 470),
        MockStep(
            kind: .completed,
            title: "All checks passed",
            detail: "Build, lint and tests are green",
            usageUsed: 520,
            message: "Done. All checks are green."
        )
    ])

    /// A connector with nothing going on.
    public static let quiet = MockScript(steps: [
        MockStep(kind: .note, title: "All quiet", detail: "No agents are running", usageUsed: 40)
    ])
}
