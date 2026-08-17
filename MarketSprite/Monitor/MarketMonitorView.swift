import SwiftUI

struct MarketMonitorView: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let maximumVisibleRows = 8

    private var rowHeight: CGFloat {
        max(
            (preferences.compactMode ? 45 : 58) * layoutScale,
            preferences.compactMode ? 39 : 46
        )
    }

    private var baseWidth: CGFloat {
        preferences.compactMode ? 460 : 560
    }

    private var layoutScale: CGFloat {
        CGFloat(min(max(preferences.displayScale, 0.65), 1.6))
    }

    private var panelInset: CGFloat {
        max(8, 10 * layoutScale)
    }

    private var panelWidth: CGFloat {
        max(baseWidth * layoutScale, minimumPanelWidth)
    }

    private var minimumPanelWidth: CGFloat {
        let columnWidths: CGFloat = preferences.compactMode
            ? 102 + 102 + 70
            : 120 + 132 + 80
        let spacing: CGFloat = preferences.compactMode ? 12 : 16
        let rowInset: CGFloat = preferences.compactMode ? 4 : 6
        return columnWidths + spacing + rowInset + panelInset * 2 + 12
    }

    private var panelHeight: CGFloat {
        let rows = max(min(store.instruments.count, maximumVisibleRows), 1)
        return CGFloat(rows) * rowHeight + panelInset * 2
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if store.instruments.isEmpty {
                    emptyState
                        .frame(height: rowHeight)
                } else {
                    ScrollView(
                        .vertical,
                        showsIndicators: store.instruments.count > maximumVisibleRows
                    ) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.instruments) { instrument in
                                let monitored = store.monitoredInstrument(for: instrument.id)
                                InstrumentRowView(
                                    instrument: instrument,
                                    quote: monitored?.quote,
                                    isLoading: monitored?.status == .loading,
                                    isStale: monitored?.status == .stale,
                                    statusMessage: monitored?.statusMessage,
                                    lineOpacity: preferences.lineOpacity,
                                    labelOpacity: preferences.labelOpacity,
                                    compact: preferences.compactMode,
                                    displayScale: preferences.displayScale
                                )
                                .equatable()
                                .frame(height: rowHeight)
                            }
                        }
                    }
                }
            }
            .padding(panelInset)
            .background(panelBackground)

            if let alert = store.activeAlert {
                AlertBannerView(alert: alert)
                    .opacity(preferences.alertOpacity)
                    .padding(.bottom, 12)
                    .transition(alertTransition)
                    .zIndex(10)
            }

            if let status = MonitorStatusIndicator(
                sourceError: store.sourceError,
                storageError: store.storageError
            ) {
                Button {
                    SettingsWindowPresenter.open { openSettings() }
                } label: {
                    BrandIcon(
                        systemName: status.icon,
                        tint: status.tint
                    )
                        .padding(7)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(status.accessibilityLabel)
                .accessibilityHint(tr("打开设置查看详情"))
                .help(status.message)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
                .zIndex(11)
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .contentShape(Rectangle())
        .onReceive(NotificationCenter.default.publisher(for: .marketSpriteOpenSettings)) { _ in
            SettingsWindowPresenter.open { openSettings() }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(response: 0.38, dampingFraction: 0.78),
            value: store.activeAlert?.id
        )
        .animation(.easeInOut(duration: 0.2), value: preferences.compactMode)
        .animation(.easeInOut(duration: 0.18), value: preferences.displayScale)
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            shape
                .fill(.ultraThinMaterial)
                .opacity(preferences.backgroundOpacity)
            shape
                .fill(Color.white.opacity(0.05 * preferences.backgroundOpacity))
            shape
                .strokeBorder(
                    Color.white.opacity(0.14 * preferences.backgroundOpacity),
                    lineWidth: 0.5
                )
        }
    }

    private var alertTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom)
                    .combined(with: .scale(scale: 0.65))
                    .combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            )
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            BrandIcon(systemName: "plus.circle.fill", showsBackground: false)
            Text("双击添加标的")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MonitorStatusIndicator: Equatable {
    case source(String)
    case storage(String)

    init?(sourceError: String?, storageError: String?) {
        if let storageError {
            self = .storage(storageError)
        } else if let sourceError {
            self = .source(sourceError)
        } else {
            return nil
        }
    }

    var icon: String {
        switch self {
        case .source:
            "network.badge.exclamationmark"
        case .storage:
            "externaldrive.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .source:
            .orange
        case .storage:
            BrandPalette.coral
        }
    }

    var message: String {
        switch self {
        case .source(let message), .storage(let message):
            message
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .source:
            tr("行情数据需要注意")
        case .storage:
            tr("本地存储需要注意")
        }
    }
}
