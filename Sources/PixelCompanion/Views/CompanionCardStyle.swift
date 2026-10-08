import SwiftUI

/// Respect Reduce Motion; tabs change immediately when animation is disabled.
enum CompanionMotion {
    static func tabTransition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }
}

/// Semantic Mac surfaces follow Light/Dark Mode and system accessibility,
/// without forced translucent overlays, fixed branding colors or extra blur.
struct CompanionCardStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(reduceTransparency ? 1 : 0.78)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

extension View {
    func companionCard() -> some View { modifier(CompanionCardStyle()) }
}
