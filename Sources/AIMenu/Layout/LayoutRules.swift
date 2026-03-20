import CoreGraphics

/// Centralized layout inputs to avoid duplicated sizing logic across pages.
enum LayoutRules {
    // Spacing system
    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing10: CGFloat = 10
    static let spacing20: CGFloat = 20

    // Radius system
    static let radiusTiny: CGFloat = 7
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 10
    static let radiusModal: CGFloat = 22
    static let radiusCard: CGFloat = 14

    static let pagePadding = CGFloat(16)
    static let sectionSpacing = CGFloat(16)
    static let cardRadius = CGFloat(14)
    static let liquidProgressHeight = CGFloat(12)
    static let liquidProgressInset = CGFloat(2)
    static let listRowSpacing = CGFloat(10)
    static let tabSwitcherMaxWidth = CGFloat(520)
    static let minimumPanelHeight = CGFloat(520)
    static let defaultPanelHeight = CGFloat(620)
    static let accountsRowSpacing = CGFloat(10)
    static let accountsExpandedColumns = 2
    static let accountsCollapsedColumns = 3
    static let accountsCardWidth = CGFloat(250)
    static let iOSAccountsExpandedColumns = 1
    static let iOSAccountsCollapsedColumns = 2
    static let iOSAccountsScrollBottomPadding = CGFloat(28)
    static let iOSBottomBarHorizontalPadding = CGFloat(16)
    static let iOSBottomBarTopInset = CGFloat(8)
    static let iOSBottomBarBottomInset = CGFloat(10)
    static let iOSNoticeCornerRadius = CGFloat(14)
    static let iOSToolbarButtonSize = CGFloat(44)
    static let toolbarIconPointSize = CGFloat(18)
    static let toolbarRefreshIconOpticalScale = CGFloat(0.82)
    static let proxyDetailCardSpacing = CGFloat(12)
    static let proxyHeroPortFieldWidth = CGFloat(108)
    static let proxyRemoteFieldMinWidth = CGFloat(160)
    static let proxyRemoteActionMinWidth = CGFloat(118)
    static let proxyRemoteMetricMinWidth = CGFloat(108)
    static let proxyRemoteMetricHeight = CGFloat(68)
    static let proxyRemoteDetailMinWidth = CGFloat(220)
    static let proxyRemoteLogsHeight = CGFloat(120)
    static let proxyPublicModeMinWidth = CGFloat(240)
    static let proxyPublicFieldMinWidth = CGFloat(220)
    static let proxyPublicStatusCardMinWidth = CGFloat(170)

    static var accountsTwoColumnContentWidth: CGFloat {
        accountsCardWidth * CGFloat(accountsExpandedColumns) + accountsRowSpacing
    }

    static var accountsPageTargetWidth: CGFloat {
        accountsTwoColumnContentWidth + pagePadding * 2
    }

    static var accountsCollapsedCardWidth: CGFloat {
        (accountsPageTargetWidth - pagePadding * 2 - accountsRowSpacing * 2) / CGFloat(accountsCollapsedColumns)
    }

    static var minimumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var defaultPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var maximumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static func iOSAccountsContentTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + pagePadding
    }

    static func iOSAccountsContentBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + iOSAccountsScrollBottomPadding
    }
}
