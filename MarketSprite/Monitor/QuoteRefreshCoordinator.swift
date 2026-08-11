import Foundation
import OSLog

struct QuoteRefreshBatch: Sendable {
    let outcomes: [QuoteRefreshOutcome]
}

struct QuoteRefreshOutcome: Sendable {
    let instrument: Instrument
    let result: Result

    enum Result: Sendable {
        case updated(QuoteSnapshot, storageError: String?)
        case stale(String)
        case failed(String)
        case discarded
    }
}

actor QuoteRefreshCoordinator {
    private static let signposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.marketsprite",
        category: "QuoteRefresh"
    )

    private let client: any MarketDataClient
    private let database: MarketDatabase
    private let maximumConcurrentRequests: Int
    private let requestLimiter: QuoteRequestLimiter

    init(
        client: any MarketDataClient,
        database: MarketDatabase,
        maximumConcurrentRequests: Int = 6
    ) {
        precondition(maximumConcurrentRequests > 0)
        self.client = client
        self.database = database
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.requestLimiter = QuoteRequestLimiter(limit: maximumConcurrentRequests)
    }

    func refresh(
        instruments: [Instrument],
        currentQuotes: [InstrumentID: QuoteSnapshot]
    ) async -> QuoteRefreshBatch {
        let interval = Self.signposter.beginInterval(
            "RefreshBatch",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("RefreshBatch", interval) }

        guard !instruments.isEmpty else {
            return QuoteRefreshBatch(outcomes: [])
        }

        let client = client
        let database = database
        let requestLimiter = requestLimiter
        var indexedOutcomes: [(Int, QuoteRefreshOutcome)] = []
        await withTaskGroup(of: (Int, QuoteRefreshOutcome).self) { group in
            let initialCount = min(maximumConcurrentRequests, instruments.count)
            for index in 0..<initialCount {
                let instrument = instruments[index]
                let currentQuote = currentQuotes[instrument.id]
                group.addTask {
                    let outcome = await requestLimiter.withPermit {
                        await Self.fetch(
                            instrument: instrument,
                            currentQuote: currentQuote,
                            client: client,
                            database: database
                        )
                    }
                    return (index, outcome)
                }
            }
            var nextIndex = initialCount

            while let outcome = await group.next() {
                indexedOutcomes.append(outcome)
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if nextIndex < instruments.count {
                    let index = nextIndex
                    let instrument = instruments[index]
                    let currentQuote = currentQuotes[instrument.id]
                    nextIndex += 1
                    group.addTask {
                        let outcome = await requestLimiter.withPermit {
                            await Self.fetch(
                                instrument: instrument,
                                currentQuote: currentQuote,
                                client: client,
                                database: database
                            )
                        }
                        return (index, outcome)
                    }
                }
            }
        }

        return QuoteRefreshBatch(
            outcomes: indexedOutcomes
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        )
    }

    private static func fetch(
        instrument: Instrument,
        currentQuote: QuoteSnapshot?,
        client: any MarketDataClient,
        database: MarketDatabase
    ) async -> QuoteRefreshOutcome {
        let interval = signposter.beginInterval(
            "FetchQuote",
            id: signposter.makeSignpostID()
        )
        defer { signposter.endInterval("FetchQuote", interval) }

        do {
            try Task.checkCancellation()
            let quote = try await client.fetchQuote(for: instrument)
            try Task.checkCancellation()
            if let currentQuote, quote.marketTime < currentQuote.marketTime {
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .stale(tr("行情源返回了较旧数据"))
                )
            }

            do {
                let persisted = try await database.saveQuote(quote, for: instrument)
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: persisted
                        ? .updated(quote, storageError: nil)
                        : .discarded
                )
            } catch {
                try Task.checkCancellation()
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .updated(quote, storageError: error.localizedDescription)
                )
            }
        } catch is CancellationError {
            return QuoteRefreshOutcome(instrument: instrument, result: .discarded)
        } catch {
            return QuoteRefreshOutcome(
                instrument: instrument,
                result: .failed(error.localizedDescription)
            )
        }
    }
}

private actor QuoteRequestLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var nextWaiterIndex = 0

    init(limit: Int) {
        availablePermits = limit
    }

    func withPermit<Result: Sendable>(
        _ operation: @Sendable () async -> Result
    ) async -> Result {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if nextWaiterIndex == waiters.count {
            waiters.removeAll(keepingCapacity: true)
            nextWaiterIndex = 0
            availablePermits += 1
        } else {
            let continuation = waiters[nextWaiterIndex]
            nextWaiterIndex += 1
            continuation.resume()
        }
    }
}
