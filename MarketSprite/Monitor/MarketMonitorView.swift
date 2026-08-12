import SwiftUI

struct MarketMonitorView: View {
    @EnvironmentObject private var store: MonitorStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openSettings) private var openSettings
    private let maximumVisibleRows = 8

    private var rowHeight: CGFloat {
        preferences.compactMode ? 45 : 58
    }

    private var baseWidth: CGFloat {
        preferences.compactMode ? 460 : 560
    }

    private var baseHeight: CGFloat {
        let rows = max(min(store.instruments.count, maximumVisibleRows), 1)
        return CGFloat(rows) * rowHeight + 20
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
                                    compact: preferences.compactMode
                                )
                                .frame(height: rowHeight)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(panelBackground)

            if let alert = store.activeAlert {
                AlertBannerView(alert: alert)
                    .opacity(preferences.alertOpacity)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.65)).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                    .zIndex(10)
            }

            if let storageError = store.storageError {
                Button {
                    SettingsWindowPresenter.open { openSettings() }
                } label: {
                    BrandIcon(systemName: "externaldrive.badge.exclamationmark")
                        .padding(7)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .help(storageError)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
                .zIndex(11)
            }
        }
        .frame(width: baseWidth, height: baseHeight)
        .contentShape(Rectangle())
        .onReceive(NotificationCenter.default.publisher(for: .marketSpriteOpenSettings)) { _ in
            SettingsWindowPresenter.open { openSettings() }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: store.activeAlert?.id)
        .animation(.easeInOut(duration: 0.2), value: preferences.compactMode)
        .scaleEffect(preferences.displayScale, anchor: .topLeading)
        .frame(
            width: baseWidth * preferences.displayScale,
            height: baseHeight * preferences.displayScale,
            alignment: .topLeading
        )
        .animation(.easeInOut(duration: 0.18), value: preferences.displayScale)
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(Color.black.opacity(preferences.backgroundOpacity))
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            BrandIcon(systemName: "plus.circle.fill", showsBackground: false)
            Text("双击添加标的")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
