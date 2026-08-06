import Foundation

struct DatabaseStartupFailure: Equatable, Sendable {
    let message: String
    let databasePath: String
}

@MainActor
final class AppBootstrap: ObservableObject {
    @Published private(set) var store: MonitorStore?
    @Published private(set) var failure: DatabaseStartupFailure?
    @Published private(set) var isStarting = false

    let preferences: AppPreferences

    private let client: any MarketDataClient
    private let databasePath: String
    private let databaseFactory: () throws -> MarketDatabase

    convenience init(
        preferences: AppPreferences,
        client: any MarketDataClient = PublicMarketDataClient()
    ) {
        let databasePath = MarketDatabase.applicationSupportDatabasePath(
            appFolderName: AppIdentity.applicationSupportFolderName
        )
        self.init(
            preferences: preferences,
            client: client,
            databasePath: databasePath,
            databaseFactory: {
                try MarketDatabase.openInApplicationSupport(
                    appFolderName: AppIdentity.applicationSupportFolderName
                )
            }
        )
    }

    init(
        preferences: AppPreferences,
        client: any MarketDataClient = PublicMarketDataClient(),
        databasePath: String,
        databaseFactory: @escaping () throws -> MarketDatabase
    ) {
        self.preferences = preferences
        self.client = client
        self.databasePath = databasePath
        self.databaseFactory = databaseFactory
    }

    func start() async {
        guard store == nil, !isStarting else { return }
        isStarting = true
        failure = nil
        defer { isStarting = false }

        do {
            let database = try databaseFactory()
            let candidate = MonitorStore(
                client: client,
                database: database,
                preferences: preferences
            )
            try await candidate.start()
            store = candidate
        } catch {
            store = nil
            failure = DatabaseStartupFailure(
                message: error.localizedDescription,
                databasePath: databasePath
            )
        }
    }

    func retry() async {
        failure = nil
        await start()
    }
}
