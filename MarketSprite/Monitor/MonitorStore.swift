import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
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
    private let alertSoundPlayer = AlertSoundPlayer()
    private var refreshTask: Task<Void, Never>?
    private var dismissAlertTask: Task<Void, Never>?
    private var alertConfigurationPersistenceTask: Task<Void, Never>?
    private var priceAlertTargetsPersistenceTask: Task<Void, Never>?
    private var watchlistMutationTail: Task<Void, Never>?
    private var hasStarted = false
    private var refreshGeneration = 0
    private var pendingWatchlistMutations = 0
    private var alertConfigurationRevision = 0
    private var priceAlertTargetsRevision = 0
    private var lastPersistedAlertConfiguration = AlertConfiguration.default
    private var lastPersistedPriceAlertTargets: [InstrumentID: PriceAlertTargets] = [:]
    private var storageErrors: [StorageErrorContext: StorageErrorEntry] = [:]
    private var storageErrorRevision = 0
    private var alertEvaluators: [InstrumentID: AlertEvaluator] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(
        client: any MarketDataClient = PublicMarketDataClient(),
        database: MarketDatabase,
        preferences: AppPreferences
    ) {
        self.client = client
        self.database = database
        self.preferences = preferences
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
            let instruments = try await database.loadWatchlist(
                defaultingTo: Instrument.initialWatchlist
            )
            let cachedQuotes = try await database.loadLatestQuotes(for: instruments)
            let loadedAlertConfiguration = try await database.loadAlertConfiguration()
            let loadedPriceAlertTargets = try await database.loadPriceAlertTargets(
                for: instruments
            )
            let loadedQuoteBarCount = try await database.quoteBarCount()

            alertConfiguration = loadedAlertConfiguration
            priceAlertTargets = loadedPriceAlertTargets
            lastPersistedAlertConfiguration = loadedAlertConfiguration
            lastPersistedPriceAlertTargets = loadedPriceAlertTargets
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
            quoteBarCount = loadedQuoteBarCount
            sourceError = nil
        } catch {
            hasStarted = false
            throw error
        }

        await refreshAll()
        restartRefreshLoop()
    }

    func stop() {
        hasStarted = false
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        alertSoundPlayer.stop()
    }

    func monitoredInstrument(for id: InstrumentID) -> MonitoredInstrument? {
        monitoredInstruments[id]
    }

    func search(_ query: String) async throws -> [Instrument] {
        try await client.searchInstruments(matching: query)
    }

    func remove(_ instrument: Instrument) async {
        guard instruments.contains(where: { $0.id == instrument.id }) else { return }
        refreshGeneration += 1
        await enqueueWatchlistMutation { [self] in
            var updated = watchlist
            updated.remove(instrument)
            guard updated != watchlist else { return }

            refreshGeneration += 1
            do {
                try await database.replaceWatchlist(with: updated.instruments)
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
            Task { await self.refreshAll() }
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
            let decoded = try JSONDecoder().decode([Instrument].self, from: data)
            guard !decoded.isEmpty else { return .failure(tr("JSON 中没有标的")) }
            let imported = Watchlist(decoded)
            refreshGeneration += 1
            return await enqueueWatchlistMutation { [self] in
                refreshGeneration += 1
                do {
                    try await database.replaceWatchlist(with: imported.instruments)

                    let keptIDs = Set(imported.instruments.map(\.id))
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
                    Task { await self.refreshAll() }
                    return .success(count: imported.instruments.count)
                } catch {
                    let message = String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                    recordStorageError(context: .watchlist, message: message)
                    Task { await self.refreshAll() }
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
                watchlist = updated
                monitoredInstruments[instrument.id] = MonitoredInstrument(
                    instrument: instrument,
                    quote: nil,
                    status: .idle,
                    statusMessage: nil
                )
                clearStorageError(context: .watchlist)
                Task { await self.refresh(instrument) }
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
        refreshGeneration += 1
        let generation = refreshGeneration
        let currentInstruments = instruments
        guard !currentInstruments.isEmpty else {
            lastRefresh = Date()
            sourceError = nil
            return
        }

        for instrument in currentInstruments {
            updateStatus(for: instrument.id, status: .loading, message: nil)
        }
        var failures = 0
        var staleResponses = 0
        var savedAnyQuote = false
        var quotePersistenceFailed = false

        await withTaskGroup(of: FetchOutcome.self) { group in
            for instrument in currentInstruments {
                group.addTask { [client] in
                    do {
                        return .success(
                            instrument,
                            try await client.fetchQuote(for: instrument)
                        )
                    } catch {
                        return .failure(
                            instrument.id,
                            error.localizedDescription
                        )
                    }
                }
            }

            for await outcome in group {
                guard generation == refreshGeneration else {
                    group.cancelAll()
                    return
                }
                switch outcome {
                case .success(let instrument, let quote):
                    guard isRefreshCurrent(
                        generation,
                        instrumentID: instrument.id
                    ) else {
                        group.cancelAll()
                        return
                    }
                    if let currentQuote = monitoredInstruments[instrument.id]?.quote,
                       quote.marketTime < currentQuote.marketTime {
                        staleResponses += 1
                        updateStatus(
                            for: instrument.id,
                            status: .stale,
                            message: tr("行情源返回了较旧数据")
                        )
                        continue
                    }

                    var saved = false
                    var shouldCommitQuote = true
                    do {
                        saved = try await database.saveQuote(quote, for: instrument)
                        shouldCommitQuote = saved
                    } catch {
                        guard isRefreshCurrent(
                            generation,
                            instrumentID: instrument.id
                        ) else {
                            group.cancelAll()
                            return
                        }
                        quotePersistenceFailed = true
                        recordStorageError(
                            context: .quoteWrite,
                            message: String(
                                format: tr("行情已更新，但写入本地数据库失败：%@"),
                                error.localizedDescription
                            )
                        )
                    }

                    guard isRefreshCurrent(
                        generation,
                        instrumentID: instrument.id
                    ) else {
                        group.cancelAll()
                        return
                    }
                    guard shouldCommitQuote else { continue }
                    if saved {
                        savedAnyQuote = true
                    }
                    monitoredInstruments[instrument.id] = MonitoredInstrument(
                        instrument: instrument,
                        quote: quote,
                        status: .live,
                        statusMessage: nil
                    )
                    evaluateAlert(for: instrument, quote: quote)
                case .failure(let id, let message):
                    failures += 1
                    if var monitored = monitoredInstruments[id] {
                        monitored.status = monitored.quote == nil ? .idle : .stale
                        monitored.statusMessage = message
                        monitoredInstruments[id] = monitored
                    }
                }
            }
        }

        guard generation == refreshGeneration else { return }
        if savedAnyQuote {
            if !quotePersistenceFailed {
                clearStorageError(context: .quoteWrite)
            }
            await reloadQuoteBarCount()
        }
        guard generation == refreshGeneration else { return }
        lastRefresh = Date()
        if failures == currentInstruments.count {
            sourceError = tr("行情连接暂不可用，已保留上次成功数据")
        } else if failures + staleResponses == currentInstruments.count {
            sourceError = tr("行情源暂未返回更新数据，已保留较新缓存")
        } else {
            sourceError = nil
        }
    }

    func refresh(_ instrument: Instrument) async {
        let generation = refreshGeneration
        updateStatus(for: instrument.id, status: .loading, message: nil)
        let quote: QuoteSnapshot
        do {
            quote = try await client.fetchQuote(for: instrument)
        } catch {
            guard isRefreshCurrent(generation, instrumentID: instrument.id) else {
                return
            }
            if var monitored = monitoredInstruments[instrument.id] {
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = error.localizedDescription
                monitoredInstruments[instrument.id] = monitored
            }
            return
        }

        guard isRefreshCurrent(generation, instrumentID: instrument.id) else { return }
        if let currentQuote = monitoredInstruments[instrument.id]?.quote,
           quote.marketTime < currentQuote.marketTime {
            updateStatus(
                for: instrument.id,
                status: .stale,
                message: tr("行情源返回了较旧数据")
            )
            return
        }

        var saved = false
        do {
            saved = try await database.saveQuote(quote, for: instrument)
            guard isRefreshCurrent(generation, instrumentID: instrument.id) else {
                return
            }
            guard saved else { return }
            clearStorageError(context: .quoteWrite)
        } catch {
            guard isRefreshCurrent(generation, instrumentID: instrument.id) else {
                return
            }
            recordStorageError(
                context: .quoteWrite,
                message: String(
                    format: tr("行情已更新，但写入本地数据库失败：%@"),
                    error.localizedDescription
                )
            )
        }

        guard isRefreshCurrent(generation, instrumentID: instrument.id) else { return }
        monitoredInstruments[instrument.id] = MonitoredInstrument(
            instrument: instrument,
            quote: quote,
            status: .live,
            statusMessage: nil
        )
        evaluateAlert(for: instrument, quote: quote)
        if saved {
            await reloadQuoteBarCount()
        }
    }

    func updateAlertConfiguration(_ configuration: AlertConfiguration) {
        guard configuration != alertConfiguration else { return }
        alertConfiguration = configuration
        alertEvaluators.removeAll()
        if !configuration.isEnabled {
            clearActiveAlert()
        }
        persistAlertConfiguration()
    }

    func updatePriceTargets(
        for instrument: Instrument,
        risingPrice: Double,
        fallingPrice: Double
    ) {
        let sanitized = PriceAlertTargets(
            risingPrice: risingPrice.isFinite ? max(0, risingPrice) : 0,
            fallingPrice: fallingPrice.isFinite ? max(0, fallingPrice) : 0
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
                    format: tr("清空行情库失败：%@"),
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

    private func updateStatus(
        for id: InstrumentID,
        status: MonitorStatus,
        message: String?
    ) {
        guard var monitored = monitoredInstruments[id] else { return }
        monitored.status = status
        monitored.statusMessage = message
        monitoredInstruments[id] = monitored
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
            persistPriceAlertTargets()
        }
    }

    private func persistAlertConfiguration() {
        let configuration = alertConfiguration
        alertConfigurationRevision += 1
        let revision = alertConfigurationRevision
        let previousTask = alertConfigurationPersistenceTask
        alertConfigurationPersistenceTask = Task { [weak self, database] in
            await previousTask?.value
            do {
                try await database.saveAlertConfiguration(configuration)
                guard let self else { return }
                self.lastPersistedAlertConfiguration = configuration
                if revision == self.alertConfigurationRevision {
                    self.clearStorageError(context: .alertConfiguration)
                }
            } catch {
                guard let self,
                      revision == self.alertConfigurationRevision
                else { return }
                self.alertConfiguration = self.lastPersistedAlertConfiguration
                self.alertEvaluators.removeAll()
                if !self.alertConfiguration.isEnabled {
                    self.clearActiveAlert()
                }
                self.recordStorageError(
                    context: .alertConfiguration,
                    message: String(
                        format: tr("提醒配置保存失败，已恢复上次保存值：%@"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private func persistPriceAlertTargets() {
        let targets = priceAlertTargets
        priceAlertTargetsRevision += 1
        let revision = priceAlertTargetsRevision
        let previousTask = priceAlertTargetsPersistenceTask
        priceAlertTargetsPersistenceTask = Task { [weak self, database] in
            await previousTask?.value
            do {
                try await database.replacePriceAlertTargets(targets)
                guard let self else { return }
                self.lastPersistedPriceAlertTargets = targets
                if revision == self.priceAlertTargetsRevision {
                    self.clearStorageError(context: .priceAlertTargets)
                }
            } catch {
                guard let self,
                      revision == self.priceAlertTargetsRevision
                else { return }
                let observedIDs = Set(self.instruments.map(\.id))
                self.applyPriceAlertTargets(
                    self.lastPersistedPriceAlertTargets.filter {
                        observedIDs.contains($0.key)
                    },
                    persist: false
                )
                self.recordStorageError(
                    context: .priceAlertTargets,
                    message: String(
                        format: tr("目标价格保存失败，已恢复上次保存值：%@"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private func enqueueWatchlistMutation<Result>(
        _ operation: @escaping @MainActor () async -> Result
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

    private func isRefreshCurrent(
        _ generation: Int,
        instrumentID: InstrumentID
    ) -> Bool {
        generation == refreshGeneration
            && instruments.contains(where: { $0.id == instrumentID })
    }

    private func reloadQuoteBarCount() async {
        do {
            quoteBarCount = try await database.quoteBarCount()
            clearStorageError(context: .quoteCount)
        } catch {
            recordStorageError(
                context: .quoteCount,
                message: String(
                    format: tr("读取行情库行数失败：%@"),
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
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let seconds = self.preferences.refreshInterval
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self.refreshAll()
            }
        }
    }

    private enum FetchOutcome: Sendable {
        case success(Instrument, QuoteSnapshot)
        case failure(InstrumentID, String)
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
        case alertConfiguration
        case priceAlertTargets
    }
}
