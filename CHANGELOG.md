# Changelog

## 0.1.0 - 2026-08-14

### Breaking

- Switched to Swift 6 complete concurrency checking and warnings-as-errors.
- Fixed the main database as `marketsprite.sqlite` with an internal structure marker; after the canonical database is established and validated, legacy database files and sidecars are archived under `Backups/` and never used as data sources again.

### Changed

- Added a single-flight refresh coordinator with a global six-request limit, deterministic batch results, and cancellation when Watchlist membership changes.
- Made quote persistence synchronize exact minute snapshots, including historical corrections and removed bars.
- Persisted alert configuration and price targets as one debounced atomic snapshot and flush pending settings before termination.
- Validated all external instrument input, removed the hard-coded A-share holiday table, and moved database counts off the refresh hot path.
- Split Settings by page, reduced chart strokes to two accumulated paths, added signposts, CI, and concurrency/database performance coverage.
- Redesigned Settings with a dedicated sidebar and consistent cards, rows, controls, and window chrome.
- Made Watchlist search cancellation-safe, latest-request-wins, retryable, and deduplicated by instrument identity.
- Batched cached quote loading and prepared chart points, ranges, and extrema in one pass to reduce startup and rendering work.

### Release

- Fresh start as MarketSprite `0.1.0`.
- Added a branded, guided macOS disk image for drag-to-install distribution.
- Native Universal build for Apple Silicon and Intel Macs.
- Standardized local installation through one verified `/Applications/MarketSprite.app` copy.

### Notes

- Public quote endpoints are not trading-grade, and unnotarized downloads may trigger a macOS source warning.
