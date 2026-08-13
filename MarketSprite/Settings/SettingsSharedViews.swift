import AppKit
import SwiftUI

struct SettingsPageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr(title))
                .font(.title2.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(tr(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(16)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A native scroll view that keeps scrolling available without showing a heavy scrollbar.
struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .scrollIndicators(.hidden)
        .background(SettingsScrollViewConfigurator())
    }
}

private struct SettingsScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAvailable(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAvailable(nsView)
    }

    private func configureWhenAvailable(_ view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = enclosingScrollView(of: view) else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
    }

    private func enclosingScrollView(of view: NSView) -> NSScrollView? {
        var candidate: NSView? = view
        while let superview = candidate?.superview {
            if let scrollView = superview as? NSScrollView {
                return scrollView
            }
            candidate = superview
        }
        return nil
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
