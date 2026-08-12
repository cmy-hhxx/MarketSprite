import AppKit
import os
import SwiftUI
import XCTest
@testable import MarketSprite

final class PerformanceBaselineTests: XCTestCase {
    func testTenInstrumentRefreshBaseline() async throws {
        try await measureRefresh(instrumentCount: 10)
    }

    func testHundredInstrumentRefreshBaseline() async throws {
        try await measureRefresh(instrumentCount: 100)
    }

    func testSynchronizingTwoHundredFortyBarsBaseline() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let snapshot = Self.snapshot(for: instrument, barCount: 240, dayOffset: 0)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                _ = try await database.saveQuote(snapshot, for: instrument)
            }
        }
    }

    func testOpeningOneYearCacheBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpritePerformance.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let instrument = Instrument.initialWatchlist[0]
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [instrument])
        for day in 0..<252 {
            _ = try await database.saveQuote(
                Self.snapshot(for: instrument, barCount: 240, dayOffset: day),
                for: instrument
            )
        }
        try await database.close()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                let reopened = try MarketDatabase.open(atPath: path)
                _ = try await reopened.loadLatestQuotes(for: [instrument])
                try await reopened.close()
            }
        }
    }

    private func measureRefresh(instrumentCount: Int) async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = (0..<instrumentCount).map { index in
            Instrument(
                symbol: "P\(index)",
                name: "性能基线 \(index)",
                namespace: .unitedStates
            )
        }
        try await database.replaceWatchlist(with: instruments)
        let coordinator = QuoteRefreshCoordinator(
            client: BenchmarkMarketDataClient(),
            database: database,
            maximumConcurrentRequests: 6
        )

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                _ = await coordinator.refresh(instruments: instruments, currentQuotes: [:])
            }
        }
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    private func waitForAsyncOperation(
        _ operation: @escaping @Sendable () async throws -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let succeeded = OSAllocatedUnfairLock(initialState: true)
        Task {
            do {
                try await operation()
            } catch {
                succeeded.withLock { $0 = false }
            }
            semaphore.signal()
        }
        XCTAssertEqual(semaphore.wait(timeout: .now() + 30), .success)
        XCTAssertTrue(succeeded.withLock { $0 })
    }

    private static func snapshot(
        for instrument: Instrument,
        barCount: Int,
        dayOffset: Int
    ) -> QuoteSnapshot {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
            .addingTimeInterval(Double(dayOffset) * 86_400)
        let bars = (0..<barCount).map { index in
            let price = 100 + Double(index) / 100
            return MinuteBar(
                time: base.addingTimeInterval(Double(index) * 60),
                open: price,
                close: price + 0.01,
                high: price + 0.02,
                low: price - 0.01
            )
        }
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: 100,
            previousClose: 99,
            lastPrice: bars.last?.close ?? 100,
            marketTime: bars.last?.time ?? base,
            receivedAt: (bars.last?.time ?? base).addingTimeInterval(1),
            source: .tencent
        )
    }
}

@MainActor
final class ChartPerformanceBaselineTests: XCTestCase {
    func testTwoThousandPointChartRenderBaseline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bars = (0..<2_000).map { index in
            let price = 100 + sin(Double(index) / 20)
            return MinuteBar(
                time: start.addingTimeInterval(Double(index) * 60),
                open: price,
                close: price,
                high: price + 0.1,
                low: price - 0.1
            )
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let renderer = ImageRenderer(
                content: IntradayChartView(
                    points: bars,
                    market: .aShare,
                    dayOpen: 100,
                    previousClose: 100,
                    colorRole: .red,
                    opacity: 1
                )
                .frame(width: 176, height: 48)
            )
            renderer.scale = 1
            XCTAssertNotNil(renderer.cgImage)
        }
    }
}

private struct BenchmarkMarketDataClient: MarketDataClient {
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
