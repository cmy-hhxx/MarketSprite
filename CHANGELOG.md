# Changelog

## v0.5.0 - 2026-08-06

### Breaking

- Removed all MingyHUD/StockPet compatibility and migrations. Existing local settings and data are reset to the new `marketSprite.*` preferences and MarketSprite SQLite schema.
- Switched the current database to `marketsprite-v2.sqlite`; the old `marketsprite.sqlite` schema is intentionally not migrated.
- Removed the local `QuoteDatabase` package and generated Xcode project; `project.yml` is now the source of truth.

### Changed

- Reorganized the application and tests by capability: `App`, `Monitor`, `MarketData`, `Alerts`, `Settings`, `Database`, `Platform`, and `Resources`.
- Added provider-independent market models and made `MonitorStore` the monitor orchestration boundary.
- Centralized SQLite/GRDB access in `MarketDatabase` and UserDefaults access in `AppPreferences`; watchlists, minute data, alerts, and price targets now persist through the database layer.
- Isolated provider identifiers and fallback behavior inside market-data adapters.
- Made `SymbolNamespace` part of every instrument identity, fixed SSE/SZSE/BSE routing and provider-clock parsing, and surfaced the namespace wherever duplicate symbols can appear.
- Removed the production in-memory fallback, serialized Watchlist and alert persistence, rejected stale refresh commits, and separated provider errors from visible storage errors.
- Added architecture documentation and automated boundary checks, expanded tests, and fixed initial-refresh race conditions.

## v0.4.0 - 2026-08-05

### Changed

- Rebranded the macOS application, target, scheme, tests, bundle identifier, and repository identity from MingyHUD/StockPet to MarketSprite.
- Made `project.yml` the reproducible Xcode project source and pinned XcodeGen with mise.
- Added non-destructive migration for legacy preferences and application-support data.
- Updated user, development, privacy, attribution, and risk documentation.

## v0.3.0

The first public release under the MingyHUD name:

- Native Universal macOS builds for Apple Silicon and Intel Macs.
- A-share, Hong Kong, and US intraday charts with unlimited watchlist entries.
- Floating-window controls, live quote refresh, and configurable bull/bear alerts.

### Notes

- Public quote endpoints are not trading-grade, and unsigned downloads may trigger a macOS source warning.
