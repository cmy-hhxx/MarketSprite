import Combine
import Foundation

@MainActor
final class WatchlistSearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            cancel()
        }
    }
    @Published private(set) var results: [Instrument] = []
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?

    private let search: (String) async throws -> [Instrument]
    private var searchTask: Task<Void, Never>?
    private var requestRevision = 0

    init(search: @escaping (String) async throws -> [Instrument]) {
        self.search = search
    }

    deinit {
        searchTask?.cancel()
    }

    func submit() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            cancel()
            return
        }

        requestRevision += 1
        let revision = requestRevision
        searchTask?.cancel()
        results = []
        message = nil
        isSearching = true

        let search = search
        searchTask = Task { [weak self] in
            do {
                let found = try await search(cleanQuery)
                guard !Task.isCancelled else { return }
                self?.applyResults(found, revision: revision)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyFailure(error, revision: revision)
            }
        }
    }

    func cancel() {
        requestRevision += 1
        searchTask?.cancel()
        searchTask = nil
        results = []
        message = nil
        isSearching = false
    }

    private func applyResults(_ found: [Instrument], revision: Int) {
        guard revision == requestRevision else { return }
        results = Self.deduplicated(found)
        message = results.isEmpty ? tr("没有找到支持的 A股、港股或美股") : nil
        isSearching = false
        searchTask = nil
    }

    private func applyFailure(_ error: Error, revision: Int) {
        guard revision == requestRevision else { return }
        message = String(
            format: tr("搜索失败：%@"),
            error.localizedDescription
        )
        isSearching = false
        searchTask = nil
    }

    private static func deduplicated(_ instruments: [Instrument]) -> [Instrument] {
        var seen = Set<InstrumentID>()
        return instruments.filter { seen.insert($0.id).inserted }
    }
}
