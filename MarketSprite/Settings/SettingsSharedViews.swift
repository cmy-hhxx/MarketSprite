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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title))
                    .font(.headline.weight(.semibold))

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
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: 1
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .padding(.vertical, 10)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
    }
}

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        HStack {
            label
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
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
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
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
        case .aShare: .red
        case .hongKong: .orange
        case .unitedStates: .blue
        }
    }
}
