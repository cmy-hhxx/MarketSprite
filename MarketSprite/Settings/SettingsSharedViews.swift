import SwiftUI

struct SettingsGroup<Content: View, Action: View>: View {
    let title: String
    @ViewBuilder let action: Action
    @ViewBuilder let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) where Action == EmptyView {
        self.title = title
        action = EmptyView()
        self.content = content()
    }

    init(
        _ title: String,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.action = action()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title))
                    .font(.system(size: 12.5, weight: .semibold))

                Spacer(minLength: 12)

                action
            }

            SettingsCard {
                content
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .padding(.vertical, 6)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.12))
    }
}

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 0) {
                label
                Spacer(minLength: 20)
            }
        }
        .toggleStyle(.switch)
        .tint(BrandPalette.interfaceAccent)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.automatic)
    }
}

struct MarketBadge: View {
    let market: Market

    var body: some View {
        Text(market.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(badgeColor)
            .background(badgeColor.opacity(0.14), in: Capsule())
    }

    private var badgeColor: Color {
        switch market {
        case .aShare: BrandPalette.coralInk
        case .hongKong: .orange
        case .unitedStates: BrandPalette.interfaceAccent
        }
    }
}
