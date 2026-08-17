import Combine
import Foundation
import OSLog

@MainActor
final class MonitorStore: ObservableObject {
    private static let signposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.marketsprite",
        category: "MonitorStore"
    )

    @Published private var watchlist = Watchlist()
    @Published private var monitoredInstruments: [InstrumentID: MonitoredInstrument] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var sourceError: String?
    @Published private(set) var storageError: String?
    @Published private(set) var quoteBarCount = 0
    @Published private(set) var isWatchlistMutating = false
    @Published var activeAlert: AlertEvent?
    @Published private(set) var alertConfiguration = AlertConfiguration.default
    @Published private(set) var priceAlertTargets: [InstrumentID: PriceAlertTargets] = [:]

    var instruments: [Instrument] { watchlist.instruments }
    var databasePath: String { database.databasePath }

    private let client: any MarketDataClient
    private let database: MarketDatabase
    private let preferences: AppPreferences
    private let refreshCoordinator: QuoteRefreshCoordinator
    private let alertSoundPlayer = AlertSoundPlayer()
    private var initialRefreshTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshCycleTask: Task<Void, Never>?
    private var refreshCycleRevision: Int?
    private var dismissAlertTask: Task<Void, Never>?
    private var alertSettingsPersistenceTask: Task<Void, Never>?
    private var watchlistMutationTail: Task<Void, Never>?
    private var hasStarted = false
    private var isShuttingDown = false
    private var watchlistRevision = 0
    private var pendingWatchlistMutations = 0
    private var alertSettingsRevision = 0
    private var lastPersistedAlertSettings = AlertSettingsSnapshot.default
    private var storageErrors: [StorageErrorContext: StorageErrorEntry] = [:]
    private var storageErrorRevision = 0
    private var alertEvaluators: [InstrumentID: AlertEvaluator] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(
        client: any MarketDataClient = PublicMarketDataClient(),
        database: MarketDatabase,
        preferences: AppPreferences,
        maximumConcurrentRefreshes: Int = 6
    ) {
        self.client = client
        self.database = database
        self.preferences = preferences
        self.refreshCoordinator = QuoteRefreshCoordinator(
            client: client,
            database: database,
            maximumConcurrentRequests: maximumConcurrentRefreshes
        )
        preferences.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartRefreshLoop()
            }
            .store(in: &cancellables)
    }

    func start() async throws {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            let instruments = try await database.loadWatchlist()
            let cachedQuotes = try await database.loadLatestQuotes(for: instruments)
            let loadedAlertSettings = try await database.loadAlertSettings()

            alertConfiguration = loadedAlertSettings.configuration
            priceAlertTargets = loadedAlertSettings.priceTargets
            lastPersistedAlertSettings = loadedAlertSettings
            watchlist = Watchlist(instruments)
            monitoredInstruments = Dictionary(
                uniqueKeysWithValues: instruments.map { instrument in
                    let quote = cachedQuotes[instrument.id]
                    return (
                        instrument.id,
                        MonitoredInstrument(
                            instrument: instrument,
                            quote: quote,
                            status: quote == nil ? .idle : .stale,
                            statusMessage: quote == nil ? nil : tr("本地缓存")
                        )
                    )
                }
            )
            sourceError = nil
        } catch {
            hasStarted = false
            throw error
        }

        restartRefreshLoop()
        scheduleInitialRefresh()
    }

    func stop() {
        hasStarted = false
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        refreshCycleTask?.cancel()
        refreshCycleTask = nil
        refreshCycleRevision = nil
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        alertSoundPlayer.stop()
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stop()
        await watchlistMutationTail?.value
        await flushPendingPersistence()
        try? await database.close()
    }

    func monitoredInstrument(for id: InstrumentID) -> MonitoredInstrument? {
        monitoredInstruments[id]
    }

    func search(_ query: String) async throws -> [Instrument] {
        try await client.searchInstruments(matching: query)
    }

    func remove(_ instrument: Instrument) async {
        guard instruments.contains(where: { $0.id == instrument.id }) else { return }
        await enqueueWatchlistMutation { [self] in
            var updated = watchlist
            updated.remove(instrument)
            guard updated != watchlist else { return }

            do {
                try await database.replaceWatchlist(with: updated.instruments)
                invalidateRefreshMembership()
                watchlist = updated
                monitoredInstruments.removeValue(forKey: instrument.id)
                alertEvaluators.removeValue(forKey: instrument.id)
                var updatedTargets = priceAlertTargets
                updatedTargets.removeValue(forKey: instrument.id)
                applyPriceAlertTargets(updatedTargets, persist: true)
                if activeAlert?.instrument.id == instrument.id {
                    clearActiveAlert()
                }
                clearStorageError(context: .watchlist)
            } catch {
                recordStorageError(
                    context: .watchlist,
                    message: String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                )
            }
            scheduleRefreshAfterWatchlistMutation()
        }
    }

    func moveInstruments(from offsets: IndexSet, to destination: Int) async {
        await enqueueWatchlistMutation { [self] in
            var reordered = watchlist
            reordered.move(from: offsets, to: destination)
            guard reordered != watchlist else { return }
            do {
                try await database.replaceWatchlist(with: reordered.instruments)
                watchlist = reordered
                clearStorageError(context: .watchlist)
            } catch {
                recordStorageError(
                    context: .watchlist,
                    message: String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    func watchlistJSONExample() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(instruments),
              let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }

    @discardableResult
    func importWatchlist(fromJSON json: String) async -> WatchlistImportResult {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(tr("请先粘贴 JSON")) }
        guard let data = trimmed.data(using: .utf8) else {
            return .failure(tr("JSON 编码无效"))
        }

        do {
            let payloads = try JSONDecoder().decode(
                [InstrumentImportPayload].self,
                from: data
            )
            var decoded: [Instrument] = []
            decoded.reserveCapacity(payloads.count)
            for (index, payload) in payloads.enumerated() {
                do {
                    decoded.append(
                        try Instrument(
                            validatingSymbol: payload.symbol,
                            name: payload.name,
                            namespace: payload.namespace
                        )
                    )
                } catch {
                    return .failure(
                        String(
                            format: tr("JSON 第 %d 个标的无效：%@"),
                            index + 1,
                            error.localizedDescription
                        )
                    )
                }
            }
            guard !decoded.isEmpty else { return .failure(tr("JSON 中没有标的")) }
            let imported = Watchlist(decoded)
            return await enqueueWatchlistMutation { [self] in
                do {
                    try await database.replaceWatchlist(with: imported.instruments)

                    let keptIDs = Set(imported.instruments.map(\.id))
                    invalidateRefreshMembership()
                    watchlist = imported
                    monitoredInstruments = Dictionary(
                        uniqueKeysWithValues: imported.instruments.map { instrument in
                            let current = monitoredInstruments[instrument.id]
                            return (
                                instrument.id,
                                MonitoredInstrument(
                                    instrument: instrument,
                                    quote: current?.quote,
                                    status: current?.status ?? .idle,
                                    statusMessage: current?.statusMessage
                                )
                            )
                        }
                    )
                    applyPriceAlertTargets(
                        priceAlertTargets.filter { keptIDs.contains($0.key) },
                        persist: true
                    )
                    alertEvaluators = alertEvaluators.filter { keptIDs.contains($0.key) }
                    if let alertID = activeAlert?.instrument.id,
                       !keptIDs.contains(alertID) {
                        clearActiveAlert()
                    }
                    clearStorageError(context: .watchlist)
                    scheduleRefreshAfterWatchlistMutation()
                    return .success(count: imported.instruments.count)
                } catch {
                    let message = String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                    recordStorageError(context: .watchlist, message: message)
                    scheduleRefreshAfterWatchlistMutation()
                    return .failure(message)
                }
            }
        } catch {
            return .failure(
                String(format: tr("JSON 解析失败：%@"), error.localizedDescription)
            )
        }
    }

    @discardableResult
    func add(_ instrument: Instrument) async -> String? {
        await enqueueWatchlistMutation { [self] in
            var updated = watchlist
            guard updated.add(instrument) else {
                return tr("这个标的已经在观察列表中")
            }

            do {
                try await database.replaceWatchlist(with: updated.instruments)
                invalidateRefreshMembership()
                watchlist = updated
                monitoredInstruments[instrument.id] = MonitoredInstrument(
                    instrument: instrument,
                    quote: nil,
                    status: .idle,
                    statusMessage: nil
                )
                clearStorageError(context: .watchlist)
                scheduleRefreshAfterWatchlistMutation()
                return nil
            } catch {
                let message = String(
                    format: tr("保存观察列表失败：%@"),
                    error.localizedDescription
                )
                recordStorageError(context: .watchlist, message: message)
                return message
            }
        }
    }

    func refreshAll() async {
        let revision = watchlistRevision
        if let refreshCycleTask, refreshCycleRevision == revision {
            await refreshCycleTask.value
            return
        }

        refreshCycleTask?.cancel()
        let currentInstruments = instruments
        guard !currentInstruments.isEmpty else {
            lastRefresh = Date()
            sourceError = nil
            refreshCycleTask = nil
            refreshCycleRevision = nil
            return
        }

        var loadingInstruments = monitoredInstruments
        for instrument in currentInstruments {
            guard var monitored = loadingInstruments[instrument.id] else { continue }
            monitored.status = .loading
            monitored.statusMessage = nil
            loadingInstruments[instrument.id] = monitored
        }
        monitoredInstruments = loadingInstruments

        let currentQuotes = Dictionary(
            uniqueKeysWithValues: currentInstruments.compactMap { instrument in
                monitoredInstruments[instrument.id]?.quote.map { (instrument.id, $0) }
            }
        )
        let coordinator = refreshCoordinator
        let task = Task { [weak self] in
            let batch = await coordinator.refresh(
                instruments: currentInstruments,
                currentQuotes: currentQuotes
            )
            guard let self,
                  !Task.isCancelled,
                  self.watchlistRevision == revision
            else { return }
            self.applyRefreshBatch(batch, expectedCount: currentInstruments.count)
        }
        refreshCycleTask = task
        refreshCycleRevision = revision
        await task.value
        if refreshCycleRevision == revision {
            refreshCycleTask = nil
            refreshCycleRevision = nil
        }
    }

    func updateAlertConfiguration(_ configuration: AlertConfiguration) {
        guard configuration != alertConfiguration else { return }
        alertConfiguration = configuration
        alertEvaluators.removeAll()
        if !configuration.isEnabled {
            clearActiveAlert()
        }
        scheduleAlertSettingsPersistence()
    }

    func updatePriceTargets(
        for instrument: Instrument,
        risingPrice: Double?,
        fallingPrice: Double?
    ) {
        let sanitized = PriceAlertTargets(
            risingPrice: risingPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            fallingPrice: fallingPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        )
        var updated = priceAlertTargets
        if sanitized.isEnabled {
            updated[instrument.id] = sanitized
        } else {
            updated.removeValue(forKey: instrument.id)
        }
        applyPriceAlertTargets(updated, persist: true)
    }

    func setPriceTargetsEnabled(for instrument: Instrument, enabled: Bool) {
        guard enabled else {
            var updated = priceAlertTargets
            updated.removeValue(forKey: instrument.id)
            applyPriceAlertTargets(updated, persist: true)
            return
        }
        guard let quote = monitoredInstruments[instrument.id]?.quote,
              quote.lastPrice > 0
        else { return }
        updatePriceTargets(
            for: instrument,
            risingPrice: quote.lastPrice * (1 + alertConfiguration.risingThreshold / 100),
            fallingPrice: quote.lastPrice * (1 - alertConfiguration.fallingThreshold / 100)
        )
    }

    @discardableResult
    func generatePriceTargetsFromCurrentQuotes() -> Int {
        var updated = priceAlertTargets
        var touched = Set<InstrumentID>()
        for instrument in instruments {
            guard let quote = monitoredInstruments[instrument.id]?.quote,
                  quote.lastPrice > 0
            else { continue }
            updated[instrument.id] = PriceAlertTargets(
                risingPrice: quote.lastPrice
                    * (1 + alertConfiguration.risingThreshold / 100),
                fallingPrice: quote.lastPrice
                    * (1 - alertConfiguration.fallingThreshold / 100)
            )
            touched.insert(instrument.id)
        }
        applyPriceAlertTargets(updated, persist: true)
        return touched.count
    }

    func clearQuoteHistory() async {
        do {
            try await database.clearQuotes()
            quoteBarCount = 0
            clearStorageError(context: .quoteClear)
            clearStorageError(context: .quoteCount)
        } catch {
            recordStorageError(
                context: .quoteClear,
                message: String(
                    format: tr("清空行情缓存失败：%@"),
                    error.localizedDescription
                )
            )
        }
    }

    func refreshQuoteBarCount() async {
        await reloadQuoteBarCount()
    }

    func dismissStorageError() {
        storageErrors.removeAll()
        storageError = nil
    }

    func testAlert(_ direction: AlertDirection) {
        let instrument = instruments.first ?? Instrument.initialWatchlist[0]
        let quote = monitoredInstruments[instrument.id]?.quote
        let targets = priceAlertTargets[instrument.id]
        let targetPrice = direction == .rising
            ? targets?.risingPrice
            : targets?.fallingPrice
        presentAlert(
            AlertEvent(
                instrument: instrument,
                changePercent: direction == .rising
                    ? alertConfiguration.risingThreshold
                    : -alertConfiguration.fallingThreshold,
                lastPrice: quote?.lastPrice ?? targetPrice ?? 0,
                targetPrice: alertConfiguration.basis == .targetPrice
                    ? targetPrice
                    : nil,
                basis: alertConfiguration.basis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func applyRefreshBatch(
        _ batch: QuoteRefreshBatch,
        expectedCount: Int
    ) {
        let interval = Self.signposter.beginInterval(
            "ApplyRefreshBatch",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("ApplyRefreshBatch", interval) }

        var updatedInstruments = monitoredInstruments
        var acceptedQuotes: [(Instrument, QuoteSnapshot)] = []
        var failures = 0
        var staleResponses = 0
        var storageFailure: String?

        for outcome in batch.outcomes {
            guard var monitored = updatedInstruments[outcome.instrument.id] else {
                continue
            }
            switch outcome.result {
            case .updated(let quote, let error):
                monitored = MonitoredInstrument(
                    instrument: outcome.instrument,
                    quote: quote,
                    status: .live,
                    statusMessage: nil
                )
                acceptedQuotes.append((outcome.instrument, quote))
                storageFailure = storageFailure ?? error
            case .noData(let message):
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = message
            case .stale(let message):
                staleResponses += 1
                monitored.status = .stale
                monitored.statusMessage = message
            case .failed(let message):
                failures += 1
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = message
            case .discarded:
                failures += 1
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = nil
            }
            updatedInstruments[outcome.instrument.id] = monitored
        }
        monitoredInstruments = updatedInstruments

        for (instrument, quote) in acceptedQuotes {
            evaluateAlert(for: instrument, quote: quote)
        }
        if let storageFailure {
            recordStorageError(
                context: .quoteWrite,
                message: String(
                    format: tr("行情已更新，但写入本地数据库失败：%@"),
                    storageFailure
                )
            )
        } else if !acceptedQuotes.isEmpty {
            clearStorageError(context: .quoteWrite)
        }

        lastRefresh = Date()
        if failures == expectedCount {
            sourceError = tr("行情连接暂不可用，已保留上次成功数据")
        } else if failures + staleResponses == expectedCount {
            sourceError = tr("行情源暂未返回更新数据，已保留较新缓存")
        } else {
            sourceError = nil
        }
    }

    private func evaluateAlert(for instrument: Instrument, quote: QuoteSnapshot) {
        guard alertConfiguration.isEnabled,
              let rule = alertConfiguration.rule(
                targets: priceAlertTargets[instrument.id]
              )
        else {
            alertEvaluators.removeValue(forKey: instrument.id)
            return
        }

        var evaluator = alertEvaluators[instrument.id] ?? AlertEvaluator()
        let direction = evaluator.evaluate(
            changePercent: quote.changePercent,
            lastPrice: quote.lastPrice,
            rule: rule
        )
        alertEvaluators[instrument.id] = evaluator
        guard let direction else { return }

        let targets = priceAlertTargets[instrument.id]
        let targetPrice: Double?
        switch (alertConfiguration.basis, direction) {
        case (.targetPrice, .rising): targetPrice = targets?.risingPrice
        case (.targetPrice, .falling): targetPrice = targets?.fallingPrice
        case (.percentage, _): targetPrice = nil
        }
        presentAlert(
            AlertEvent(
                instrument: instrument,
                changePercent: quote.changePercent,
                lastPrice: quote.lastPrice,
                targetPrice: targetPrice,
                basis: alertConfiguration.basis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func presentAlert(_ alert: AlertEvent) {
        activeAlert = alert
        let soundEnabled = alert.direction == .rising
            ? preferences.bullSoundEnabled
            : preferences.bearSoundEnabled
        alertSoundPlayer.play(alert.direction, isEnabled: soundEnabled)
        dismissAlertTask?.cancel()
        dismissAlertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.activeAlert = nil
        }
    }

    private func clearActiveAlert() {
        activeAlert = nil
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        alertSoundPlayer.stop()
    }

    private func applyPriceAlertTargets(
        _ targets: [InstrumentID: PriceAlertTargets],
        persist: Bool
    ) {
        guard targets != priceAlertTargets else { return }
        let changedIDs = Set(priceAlertTargets.keys)
            .union(targets.keys)
            .filter { priceAlertTargets[$0] != targets[$0] }
        priceAlertTargets = targets
        for id in changedIDs {
            alertEvaluators.removeValue(forKey: id)
        }
        if persist {
            scheduleAlertSettingsPersistence()
        }
    }

    func flushPendingPersistence() async {
        alertSettingsPersistenceTask?.cancel()
        alertSettingsPersistenceTask = nil
        alertSettingsRevision += 1
        let revision = alertSettingsRevision
        let snapshot = currentAlertSettings
        guard snapshot != lastPersistedAlertSettings else { return }
        await persistAlertSettings(snapshot, revision: revision)
    }

    private var currentAlertSettings: AlertSettingsSnapshot {
        AlertSettingsSnapshot(
            configuration: alertConfiguration,
            priceTargets: priceAlertTargets
        )
    }

    private func scheduleAlertSettingsPersistence() {
        alertSettingsRevision += 1
        let revision = alertSettingsRevision
        let snapshot = currentAlertSettings
        alertSettingsPersistenceTask?.cancel()
        alertSettingsPersistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.persistAlertSettings(snapshot, revision: revision)
        }
    }

    private func persistAlertSettings(
        _ snapshot: AlertSettingsSnapshot,
        revision: Int
    ) async {
        do {
            try await database.saveAlertSettings(snapshot)
            guard revision == alertSettingsRevision else { return }
            lastPersistedAlertSettings = snapshot
            alertSettingsPersistenceTask = nil
            clearStorageError(context: .alertSettings)
        } catch {
            guard revision == alertSettingsRevision else { return }
            let observedIDs = Set(instruments.map(\.id))
            alertConfiguration = lastPersistedAlertSettings.configuration
            priceAlertTargets = lastPersistedAlertSettings.priceTargets.filter {
                observedIDs.contains($0.key)
            }
            alertEvaluators.removeAll()
            if !alertConfiguration.isEnabled {
                clearActiveAlert()
            }
            alertSettingsPersistenceTask = nil
            recordStorageError(
                context: .alertSettings,
                message: String(
                    format: tr("提醒设置保存失败，已恢复上次保存值：%@"),
                    error.localizedDescription
                )
            )
        }
    }

    private func enqueueWatchlistMutation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    ) async -> Result {
        pendingWatchlistMutations += 1
        isWatchlistMutating = true
        let previousTask = watchlistMutationTail
        let operationTask = Task { @MainActor in
            await previousTask?.value
            return await operation()
        }
        watchlistMutationTail = Task { @MainActor in
            _ = await operationTask.value
        }

        let result = await operationTask.value
        pendingWatchlistMutations -= 1
        isWatchlistMutating = pendingWatchlistMutations > 0
        return result
    }

    private func invalidateRefreshMembership() {
        watchlistRevision += 1
        refreshCycleTask?.cancel()
        refreshCycleTask = nil
        refreshCycleRevision = nil
    }

    private func scheduleRefreshAfterWatchlistMutation() {
        guard hasStarted, !isShuttingDown else { return }
        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    private func scheduleInitialRefresh() {
        initialRefreshTask?.cancel()
        initialRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll()
            guard !Task.isCancelled else { return }
            self.initialRefreshTask = nil
        }
    }

    private func reloadQuoteBarCount() async {
        do {
            quoteBarCount = try await database.quoteBarCount()
            clearStorageError(context: .quoteCount)
        } catch {
            recordStorageError(
                context: .quoteCount,
                message: String(
                    format: tr("读取缓存分钟数失败：%@"),
                    error.localizedDescription
                )
            )
        }
    }

    private func recordStorageError(
        context: StorageErrorContext,
        message: String
    ) {
        storageErrorRevision += 1
        storageErrors[context] = StorageErrorEntry(
            message: message,
            revision: storageErrorRevision
        )
        publishLatestStorageError()
    }

    private func clearStorageError(context: StorageErrorContext) {
        guard storageErrors.removeValue(forKey: context) != nil else { return }
        publishLatestStorageError()
    }

    private func publishLatestStorageError() {
        storageError = storageErrors.values.max {
            $0.revision < $1.revision
        }?.message
    }

    private func restartRefreshLoop() {
        guard hasStarted else { return }
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let seconds = self.preferences.refreshInterval
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self.refreshAll()
            }
        }
    }

    private struct StorageErrorEntry {
        let message: String
        let revision: Int
    }

    private enum StorageErrorContext: Hashable {
        case watchlist
        case quoteWrite
        case quoteCount
        case quoteClear
        case alertSettings
    }

    private struct InstrumentImportPayload: Decodable {
        let symbol: String
        let name: String
        let namespace: SymbolNamespace
    }
}
