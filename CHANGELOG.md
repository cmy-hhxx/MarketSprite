# Changelog

## v0.4.0 - 2026-08-05

### Changed

- Rebranded the macOS application, target, scheme, tests, bundle identifier, and repository identity from MingyHUD/StockPet to MarketSprite.
- Made `project.yml` the reproducible Xcode project source and pinned XcodeGen with mise.
- Rewrote the user, development, privacy, attribution, and risk documentation.

### Compatibility

- Copies legacy MingyHUD preferences without overwriting current MarketSprite values.
- Copies the legacy application-support directory without deleting the original or overwriting current files.
- Keeps existing preference keys and the floating-window frame key for upgrade compatibility.

### Assets

- App icons, alert sounds, and all files under `StockPet/Resources` are unchanged in this release.

## v0.3.0

The first public release under the MingyHUD name.

### Highlights

- Native Universal macOS builds for Apple Silicon and Intel Macs.
- A-share, Hong Kong, and US intraday charts with unlimited watchlist entries.
- Market-aware red/green conventions and consistent chart, name, ticker, price, and change colors.
- Independent opacity controls, overall scaling, dragging, always-on-top, mouse passthrough, and a customizable global show/hide shortcut.
- Bull and bear alerts based on either change from the previous close or per-stock target prices.
- Live quote refresh with one-click target generation from the current price.
- Alert opacity, independent sounds, and hysteresis-based anti-repeat logic.

### Notes

- Public quote endpoints may be delayed, rate-limited, or changed and should not be treated as trading-grade data.
- The downloadable apps are not signed with a commercial code-signing certificate, so the operating system may show a source warning on first launch.
