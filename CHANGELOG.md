# Changelog

## v0.1.0 - 2026-08-12

### Breaking

- Switched to Swift 6 complete concurrency checking and warnings-as-errors.
- Replaced the migration chain with one current schema in `marketsprite-v3.sqlite`; v2 data is intentionally neither read nor migrated.

### Changed

- Added a single-flight refresh coordinator with a global six-request limit, deterministic batch results, and cancellation when Watchlist membership changes.
- Made quote persistence synchronize exact minute snapshots, including historical corrections and removed bars.
- Persisted alert configuration and price targets as one debounced atomic snapshot and flush pending settings before termination.
- Validated all external instrument input, removed the hard-coded A-share holiday table, and moved database counts off the refresh hot path.
- Split Settings by page, reduced chart strokes to two accumulated paths, added signposts, CI, and concurrency/database performance coverage.

### Release

- Fresh start as MarketSprite `0.1.0`.
- Added a branded, guided macOS disk image for drag-to-install distribution.
- Native Universal build for Apple Silicon and Intel Macs.

### Notes

- Public quote endpoints are not trading-grade, and unnotarized downloads may trigger a macOS source warning.
