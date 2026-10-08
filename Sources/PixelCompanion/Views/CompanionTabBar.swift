import SwiftUI

/// Reusable 4-destination tab strip for notch and narrow menu-bar detail.
struct CompanionTabBar: View {
    @Binding var selectedTab: CompanionDetailTab
    let reduceMotion: Bool

    private func navigate(to tab: CompanionDetailTab) {
        withAnimation(CompanionMotion.tabTransition(reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CompanionDetailTab.allCases) { tab in
                Button {
                    navigate(to: tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.label)
                            .font(.system(
                                size: 10, weight: selectedTab == tab ? .semibold : .medium
                            ))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(selectedTab == tab ? 0.18 : 0.04))
                    )
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 24, height: 2)
                                .padding(.bottom, 1)
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(tab.keyboardNumber), modifiers: [.command])
                .accessibilityLabel(tab.label + " tab")
                .accessibilityValue(selectedTab == tab ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("companion.tab." + tab.rawValue)
            }
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: navigate(to: selectedTab.moving(by: -1))
            case .right: navigate(to: selectedTab.moving(by: 1))
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.tabs")
    }

}
