import Foundation

/// An ephemeral reading, not an estimate or an assertion about every screen.
struct DisplayBrightnessSnapshot: Equatable, Sendable {
    let percentage: Int?

    static let unavailable = DisplayBrightnessSnapshot(percentage: nil)

    static func validated(_ scalar: Double?) -> DisplayBrightnessSnapshot {
        guard let scalar, scalar.isFinite, (0.0...1.0).contains(scalar) else {
            return .unavailable
        }
        return DisplayBrightnessSnapshot(percentage: Int((scalar * 100).rounded()))
    }
}

// Never attribute a service's value to a particular display when IOKit
// returns more than one candidate or none at all.
enum DisplayBrightnessSelection {
    static func unambiguous(_ value: Double?, serviceCount: Int) -> Double? {
        guard serviceCount == 1 else { return nil }
        return value
    }
}
