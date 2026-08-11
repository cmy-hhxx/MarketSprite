#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failed=0

fail() {
  printf 'architecture check failed: %s\n' "$1" >&2
  failed=1
}

for directory in App Monitor MarketData Alerts Settings Database Platform Resources; do
  if [[ ! -d "MarketSprite/$directory" ]]; then
    fail "missing MarketSprite/$directory"
  fi
done

for directory in Alerts Database MarketData Monitor Settings Support; do
  if [[ ! -d "MarketSpriteTests/$directory" ]]; then
    fail "missing MarketSpriteTests/$directory"
  fi
done

if [[ ! -d "MarketSpritePerformanceTests" ]]; then
  fail "missing MarketSpritePerformanceTests"
fi

for path in StockPet Tools Packages MarketSprite/Models MarketSprite/Services MarketSprite/Stores MarketSprite/Views; do
  if [[ -e "$path" ]]; then
    fail "obsolete path still exists: $path"
  fi
done

if matches=$(rg -n \
  'MingyHUD|stockPet\.|QuoteDatabase|AShareCalendar|IntradayPoint|StockStore|StockSymbol|StockQuote|FloatingPet|MascotAlert|StockRow' \
  MarketSprite MarketSpriteTests project.yml); then
  printf '%s\n' "$matches" >&2
  fail "legacy names remain in active code or project configuration"
fi

if matches=$(rg -l '^import GRDB$' MarketSprite | rg -v '^MarketSprite/Database/'); then
  printf '%s\n' "$matches" >&2
  fail "GRDB is imported outside Database"
fi

if matches=$(rg -l '\bUserDefaults\b|@AppStorage' MarketSprite \
  | rg -v '^MarketSprite/Settings/AppPreferences\.swift$'); then
  printf '%s\n' "$matches" >&2
  fail "UserDefaults is accessed outside AppPreferences"
fi

if matches=$(rg -l '\bURLSession\b|URLRequest|data\(for:' MarketSprite \
  | rg -v '^MarketSprite/MarketData/PublicMarketDataClient\.swift$'); then
  printf '%s\n' "$matches" >&2
  fail "provider networking is implemented outside PublicMarketDataClient"
fi

if matches=$(rg -n 'DatabaseMigrator|registerMigration|v1_watchlist|v2_quotes|v3_alerts|v4_metadata' \
  MarketSprite MarketSpriteTests); then
  printf '%s\n' "$matches" >&2
  fail "legacy migration chain remains"
fi

if matches=$(rg -n 'marketsprite-v2\.sqlite' MarketSprite MarketSpriteTests project.yml); then
  printf '%s\n' "$matches" >&2
  fail "legacy v2 database is referenced by active code"
fi

if ! rg -q '^\s*- path: MarketSprite$' project.yml; then
  fail "project.yml does not use MarketSprite as its source root"
fi

marketing_version=$(yq -r '.settings.base.MARKETING_VERSION' project.yml)
if [[ ! "$marketing_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "project.yml has an invalid MARKETING_VERSION"
fi

if [[ "$(yq -r '.settings.base.SWIFT_VERSION' project.yml)" != "6.0" ]]; then
  fail "project.yml does not use Swift 6"
fi

if [[ "$(yq -r '.settings.base.SWIFT_STRICT_CONCURRENCY' project.yml)" != "complete" ]]; then
  fail "project.yml does not enable complete concurrency checking"
fi

if [[ "$(yq -r '.settings.base.SWIFT_TREAT_WARNINGS_AS_ERRORS' project.yml)" != "YES" ]]; then
  fail "project.yml does not treat Swift warnings as errors"
fi

if ! git check-ignore --no-index -q MarketSprite.xcodeproj/project.pbxproj; then
  fail "generated Xcode project is not ignored"
fi

if ! git check-ignore --no-index -q MarketSprite.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; then
  fail "generated Package.resolved is not ignored"
fi

if (( failed != 0 )); then
  exit 1
fi

printf 'architecture check passed\n'
