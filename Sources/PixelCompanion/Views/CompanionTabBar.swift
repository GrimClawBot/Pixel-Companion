import SwiftUI

/// Compact native-style selection, shared between notch and menu-bar popovers.
struct CompanionTabBar: View {
    @Binding var selectedTab: CompanionDetailTab
    let reduceMotion: Bool

    private func navigate(to tab: CompanionDetailTab) {
        withAnimation(CompanionMotion.tabTransition(reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }

    var body: some View {
        HStack(spacing: 3) {
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
                    .frame(height: 43)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
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
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
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
