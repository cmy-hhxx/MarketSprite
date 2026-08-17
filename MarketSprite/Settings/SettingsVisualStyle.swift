import AppKit
import SwiftUI

enum SettingsVisualStyle {
    static let trafficLightLeadingInset: CGFloat = 19
    static let sidebarWidth: CGFloat = 180
    static let sidebarHorizontalPadding: CGFloat = 10
    static let sidebarTopPadding: CGFloat = 47
    static let sidebarRowHeight: CGFloat = 30
    static let sidebarRowSpacing: CGFloat = 6
    static let sidebarRowHorizontalPadding: CGFloat = 7
    static let sidebarIconSize: CGFloat = 22
    static let sidebarRowCornerRadius: CGFloat = 8
    static let contentHorizontalPadding: CGFloat = 24
    static let contentMaxWidth: CGFloat = 540
    static let searchControlHeight: CGFloat = 36
    static let listHeaderHeight: CGFloat = 44
    static let watchlistRowHeight: CGFloat = 44

    static let pageTitleFontSize: CGFloat = 19
    static let sidebarFontSize: CGFloat = 12.5
    static let toolbarLabelFontSize: CGFloat = 13
    static let controlFontSize: CGFloat = 12.5
    static let listHeaderFontSize: CGFloat = 11.5
    static let instrumentNameFontSize: CGFloat = 13
    static let metadataFontSize: CGFloat = 11
    static let changeFontSize: CGFloat = 13

    static let windowBackgroundColor = NSColor(
        red: 250 / 255,
        green: 251 / 255,
        blue: 252 / 255,
        alpha: 1
    )
    static let fieldBackgroundColor = NSColor.white

    static let contentBackground = Color(nsColor: windowBackgroundColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.72)
    static let hoverBackground = Color.primary.opacity(0.035)
    static let selectedBackground = Color.primary.opacity(0.085)
    static let fieldBackground = Color(nsColor: fieldBackgroundColor)
    static let marketRed = Color(red: 217 / 255, green: 75 / 255, blue: 75 / 255)
    static let marketGreen = Color(red: 11 / 255, green: 136 / 255, blue: 117 / 255)
}
