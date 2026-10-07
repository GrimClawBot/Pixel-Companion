import Foundation

/// The three sizes of the notch UI.
public enum NotchSurface: String, CaseIterable, Sendable {
    /// Character and status squeezed beside the camera housing.
    case compact
    /// Hover preview: current activity, approvals and usage.
    case snapshot
    /// Pinned by a click: full activity feed, chat and controls.
    case detail
}

public enum NotchEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case clicked
    /// Escape, a click outside the panel, or a display change.
    case dismissed
}

/// Pure state machine for hover and click behaviour of the notch panel.
public struct NotchInteraction: Equatable, Sendable {
    public private(set) var surface: NotchSurface

    public init(surface: NotchSurface = .compact) {
        self.surface = surface
    }

    /// Applies `event`; returns `true` when the surface changed.
    @discardableResult
    public mutating func handle(_ event: NotchEvent) -> Bool {
        let next = Self.surface(after: event, from: surface)
        guard next != surface else { return false }
        surface = next
        return true
    }

    static func surface(after event: NotchEvent, from surface: NotchSurface) -> NotchSurface {
        switch (surface, event) {
        case (.compact, .pointerEntered): return .snapshot
        case (.snapshot, .pointerExited): return .compact
        case (_, .clicked): return .detail
        case (_, .dismissed): return .compact
        // The detail view stays pinned while the pointer wanders off.
        default: return surface
        }
    }
}
