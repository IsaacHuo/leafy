import SwiftUI

nonisolated enum RootTabBadgeVisibility {
    static func showsCommunityBadge(unreadCount: Int) -> Bool {
        unreadCount > 0
    }
}

struct RootFloatingTabBar: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    @Binding var selectedTab: RootTab
    let communityUnreadCount: Int
    let isCommunityEnabled: Bool

    static func reservedHeight(controlScale: CGFloat) -> CGFloat {
        74 * controlScale
    }

    static func floatingPanelMaxHeight(controlScale: CGFloat) -> CGFloat {
        334 * controlScale
    }

    static func academicSwitcherPanelMaxHeight(tabCount: Int, controlScale: CGFloat) -> CGFloat {
        guard tabCount > 5 else {
            return floatingPanelMaxHeight(controlScale: controlScale)
        }

        let rowHeight = 48 * controlScale
        let rowSpacing = 6 * controlScale
        let panelPadding = 16 * controlScale
        return CGFloat(tabCount) * rowHeight + CGFloat(tabCount - 1) * rowSpacing + panelPadding
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = RootFloatingTabBarMetrics(width: proxy.size.width, controlScale: leafyControlScale)

            LeafyGlassGroup(spacing: metrics.controlSpacing) {
                tabCapsule(hidesLabels: metrics.hidesLabels)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .frame(height: RootFloatingTabBar.reservedHeight(controlScale: leafyControlScale))
    }

    private func tabCapsule(hidesLabels: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(RootTab.visibleCases(isCommunityEnabled: isCommunityEnabled)) { tab in
                RootFloatingTabItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    showsBadge: isCommunityEnabled && tab == .community && RootTabBadgeVisibility.showsCommunityBadge(unreadCount: communityUnreadCount),
                    language: leafyLanguage,
                    themeColorPreference: themeColorPreference,
                    hidesLabel: hidesLabels
                ) {
                    selectedTab = tab
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(5 * leafyControlScale)
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
        .leafyGlassSurface(
            in: Capsule(),
            fallbackFill: Color(uiColor: .systemBackground).opacity(0.88)
        )
    }

    private var barHeight: CGFloat {
        58 * leafyControlScale
    }
}

private struct RootFloatingTabBarMetrics {
    let horizontalPadding: CGFloat
    let controlSpacing: CGFloat
    let hidesLabels: Bool

    init(width: CGFloat, controlScale: CGFloat) {
        let narrow = width < 390 * controlScale
        horizontalPadding = narrow ? 8 * controlScale : AppSpacing.page
        controlSpacing = narrow ? 8 * controlScale : 14 * controlScale
        hidesLabels = width < 340 * controlScale
    }
}

private struct RootFloatingTabItem: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyControlScale) private var leafyControlScale

    let tab: RootTab
    let isSelected: Bool
    let showsBadge: Bool
    let language: AppLanguagePreference
    let themeColorPreference: AppThemeColorPreference
    let hidesLabel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: hidesLabel ? 0 : 2 * leafyControlScale) {
                    Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                        .font(.system(size: 20 * leafyControlScale, weight: .semibold))
                        .frame(height: 21 * leafyControlScale)

                    if !hidesLabel {
                        Text(tab.title(language: language))
                            .font(.system(size: 11.5 * leafyControlScale, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsBadge {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8 * leafyControlScale, height: 8 * leafyControlScale)
                        .overlay(
                            Circle()
                                .stroke(Color(uiColor: .systemBackground), lineWidth: 1.2 * leafyControlScale)
                        )
                        .padding(.top, 7 * leafyControlScale)
                        .padding(.trailing, 14 * leafyControlScale)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.accent(for: themeColorPreference) : AppTheme.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected
                    ? AppTheme.floatingChromeSelectedBackground(for: themeColorPreference, colorScheme: colorScheme)
                    : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title(language: language))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
