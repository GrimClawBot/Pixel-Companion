import Foundation

/// What the companion character is expressing.
public enum CharacterMood: String, CaseIterable, Sendable {
    case idle
    case working
    case waitingForApproval
    case error
    case offline
    case thinking
    case coding
    case testing
    case reviewing
    case success
    case budgetWarning
    case infrastructureAlert
    case securityAlert

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waitingForApproval: return "Waiting for approval"
        case .error: return "Error"
        case .offline: return "Offline"
        case .thinking: return "Thinking"
        case .coding: return "Coding"
        case .testing: return "Testing"
        case .reviewing: return "Reviewing"
        case .success: return "Completed"
        case .budgetWarning: return "Budget warning"
        case .infrastructureAlert: return "Infrastructure alert"
        case .securityAlert: return "Security alert"
        }
    }

    /// SF Symbol used where the pixel character does not fit (menu bar, accessibility).
    public var symbolName: String {
        switch self {
        case .idle: return "face.smiling"
        case .working: return "hammer"
        case .waitingForApproval: return "hand.raised"
        case .error: return "exclamationmark.triangle"
        case .offline: return "wifi.slash"
        case .thinking: return "brain"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .testing: return "checkmark.seal"
        case .reviewing: return "eye"
        case .success: return "sparkles"
        case .budgetWarning: return "dollarsign.circle"
        case .infrastructureAlert: return "server.rack"
        case .securityAlert: return "lock.shield"
        }
    }
}

/// A mood change, for driving one-shot animations.
public struct CharacterTransition: Equatable, Sendable {
    public let previous: CharacterMood
    public let current: CharacterMood

    public init(previous: CharacterMood, current: CharacterMood) {
        self.previous = previous
        self.current = current
    }
}

/// Derives the character's mood from connector state and records transitions.
///
/// Precedence, highest first:
/// 1. not connected (`.disconnected`, `.connecting`) → `.offline`
/// 2. connection `.error` → `.error`
/// 3. any pending approval → `.waitingForApproval`
/// 4. current activity `.failed` → `.error`
/// 5. current activity `.running` → `.working`
/// 6. otherwise → `.idle`
public struct CharacterStateMachine: Equatable, Sendable {
    public private(set) var mood: CharacterMood
    public private(set) var lastTransition: CharacterTransition?
    public private(set) var transitionCount = 0

    public init(initialMood: CharacterMood = .offline) {
        mood = initialMood
    }

    public static func mood(
        for snapshot: ConnectorSnapshot, now: Date = Date()
    ) -> CharacterMood {
        switch snapshot.connectionState {
        case .disconnected, .connecting:
            return .offline
        case .error:
            return .error
        case .connected:
            break
        }
        // One shared resolver handles verified semantic events, approval precedence,
        // and expiry of transient completions. No title-based classification.
        if let primary = CompanionLiveActivityResolver.primary(
            for: snapshot, isLive: true, now: now
        ) {
            return primary.kind.characterMood
        }
        if !snapshot.pendingApprovals.isEmpty {
            return .waitingForApproval
        }
        switch snapshot.currentActivity?.kind {
        case .failed: return .error
        case .running: return .working
        case .note, .completed, nil: return .idle
        }
    }

    /// Moves to the mood for `snapshot`; returns the transition, or `nil` if the mood is unchanged.
    @discardableResult
    public mutating func update(
        with snapshot: ConnectorSnapshot, now: Date = Date()
    ) -> CharacterTransition? {
        let next = Self.mood(for: snapshot, now: now)
        guard next != mood else { return nil }
        let transition = CharacterTransition(previous: mood, current: next)
        mood = next
        lastTransition = transition
        transitionCount += 1
        return transition
    }
}
