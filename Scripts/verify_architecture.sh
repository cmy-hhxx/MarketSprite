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

if ! rg -q '^\s*- path: MarketSprite$' project.yml; then
  fail "project.yml does not use MarketSprite as its source root"
fi

if ! rg -q '^\s*MARKETING_VERSION: 0\.5\.0$' project.yml; then
  fail "project.yml is not versioned as 0.5.0"
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
