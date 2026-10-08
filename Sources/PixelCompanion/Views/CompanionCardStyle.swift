import SwiftUI

/// Accessibility controls animation policy. A disabled animation is not a zero-duration slide.
enum CompanionMotion {
    static func tabTransition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }
}

/// Quiet native card material for compact panels, not a new window or theme.
struct CompanionCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
    }
}

extension View {
    func companionCard() -> some View { modifier(CompanionCardStyle()) }
}
