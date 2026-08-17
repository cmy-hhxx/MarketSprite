import AppKit
import SwiftUI
import XCTest
@testable import MarketSprite

@MainActor
final class SettingsPerformanceTests: XCTestCase {
    func testTenInstrumentSettingsFirstRenderBaseline() async throws {
        let fixture = try await makeFixture(instrumentCount: 10)
        defer { fixture.store.stop() }

        measure(metrics: metrics, options: options) {
            let host = makeHost(fixture: fixture, section: .watchlist)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testHundredInstrumentSettingsFirstRenderBaseline() async throws {
        let fixture = try await makeFixture(
            instrumentCount: 100,
            alertBasis: .targetPrice
        )
        defer { fixture.store.stop() }

        measure(metrics: metrics, options: options) {
            let host = makeHost(fixture: fixture, section: .alerts)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testTenInstrumentSettingsSectionSwitchBaseline() async throws {
        let fixture = try await makeFixture(instrumentCount: 10)
        defer { fixture.store.stop() }
        let host = makeHost(fixture: fixture, section: .watchlist)
        host.layoutSubtreeIfNeeded()

        measure(metrics: metrics, options: options) {
            for _ in 0..<5 {
                for section in SettingsSection.allCases {
                    host.rootView = SettingsBenchmarkRoot(
                        section: section,
                        store: fixture.store,
                        preferences: fixture.preferences,
                        loginItem: fixture.loginItem
                    )
                    host.layoutSubtreeIfNeeded()
                }
            }
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testHundredInstrumentSettingsSectionSwitchBaseline() async throws {
        let fixture = try await makeFixture(
            instrumentCount: 100,
            alertBasis: .targetPrice
        )
        defer { fixture.store.stop() }
        let host = makeHost(fixture: fixture, section: .watchlist)
        host.layoutSubtreeIfNeeded()

        measure(metrics: metrics, options: options) {
            for _ in 0..<5 {
                for section in SettingsSection.allCases {
                    host.rootView = SettingsBenchmarkRoot(
                        section: section,
                        store: fixture.store,
                        preferences: fixture.preferences,
                        loginItem: fixture.loginItem
                    )
                    host.layoutSubtreeIfNeeded()
                }
            }
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    private let metrics: [XCTMetric] = [
        XCTClockMetric(),
        XCTMemoryMetric(),
    ]

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    private func makeFixture(
        instrumentCount: Int,
        alertBasis: AlertBasis = .percentage
    ) async throws -> SettingsFixture {
        let database = try MarketDatabase.inMemory()
        let instruments = (0..<instrumentCount).map { index in
            Instrument(
                symbol: "S\(index)",
                name: "设置基线 \(index)",
                namespace: .unitedStates
            )
        }
        try await database.replaceWatchlist(with: instruments)
        var alertConfiguration = AlertConfiguration.default
        alertConfiguration.basis = alertBasis
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: alertConfiguration,
                priceTargets: [:]
            )
        )

        let suiteName = "MarketSprite.SettingsPerformance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = AppPreferences(defaults: defaults)
        let store = MonitorStore(
            client: SettingsBenchmarkMarketDataClient(),
            database: database,
            preferences: preferences
        )
        try await store.start()
        store.stop()

        return SettingsFixture(
            store: store,
            preferences: preferences,
            loginItem: LoginItemController()
        )
    }

    private func makeHost(
        fixture: SettingsFixture,
        section: SettingsSection
    ) -> NSHostingView<SettingsBenchmarkRoot> {
        let host = NSHostingView(
            rootView: SettingsBenchmarkRoot(
                section: section,
                store: fixture.store,
                preferences: fixture.preferences,
                loginItem: fixture.loginItem
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 780, height: 660)
        return host
    }
}

@MainActor
private struct SettingsBenchmarkRoot: View {
    let section: SettingsSection
    let store: MonitorStore
    let preferences: AppPreferences
    let loginItem: LoginItemController

    var body: some View {
        SettingsDetailView(
            section: section,
            hasLoadedQuoteBarCount: .constant(true)
        )
        .environmentObject(store)
        .environmentObject(preferences)
        .environmentObject(loginItem)
        .frame(width: 780, height: 660)
    }
}

@MainActor
private struct SettingsFixture {
    let store: MonitorStore
    let preferences: AppPreferences
    let loginItem: LoginItemController
}

private struct SettingsBenchmarkMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [
                MinuteBar(time: time, open: 99, close: 100, high: 101, low: 98),
            ],
            dayOpen: 99,
            previousClose: 98,
            lastPrice: 100,
            marketTime: time,
            receivedAt: time.addingTimeInterval(1),
            source: .tencent
        )
    }
}
