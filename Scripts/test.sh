#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
mode=${1:-standard}
installed_app="/Applications/MarketSprite.app"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

# Current identity plus identities used by this project before the MarketSprite rebrand.
managed_bundle_identifiers=(
  "io.github.cmy-hhxx.marketsprite"
  "com.mingyhud.app"
  "com.bingge.StockPet"
  "com.bingge.StockPetEnglish"
)

app_bundle_identifier() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

is_managed_app() {
  local identifier
  identifier=$(app_bundle_identifier "$1")

  for managed_identifier in $managed_bundle_identifiers; do
    if [[ "$identifier" == "$managed_identifier" ]]; then
      return 0
    fi
  done

  return 1
}

matching_apps() {
  local root
  local -a top_level_roots
  local -a recursive_roots

  top_level_roots=(
    /Applications
    "$HOME/Applications"
    "$HOME/Desktop"
    "$HOME/Downloads"
  )
  recursive_roots=(
    "$HOME/Library/Developer/Xcode/DerivedData"
    "$root_dir/build"
    "$root_dir/.build"
  )

  for root in $top_level_roots; do
    [[ -d "$root" ]] || continue
    while IFS= read -r info_path; do
      candidate="${info_path:h:h}"
      [[ "${candidate:t}" == *.app ]] || continue
      [[ "${candidate:h:A}" == "${root:A}" ]] || continue
      print -- "$candidate"
    done < <(rg --files --hidden --no-ignore --glob 'Info.plist' "$root" 2>/dev/null)
  done

  for root in $recursive_roots; do
    [[ -d "$root" ]] || continue
    while IFS= read -r info_path; do
      candidate="${info_path:h:h}"
      [[ "${candidate:t}" == *.app ]] || continue
      print -- "$candidate"
    done < <(rg --files --hidden --no-ignore --glob 'Info.plist' "$root" 2>/dev/null)
  done
}

registered_app_paths() {
  "$lsregister_path" -dump 2>/dev/null | awk '
    /^path:/ {
      path = $0
      sub(/^path:[[:space:]]*/, "", path)
      sub(/[[:space:]]+\([^)]*\)$/, "", path)
      next
    }
    /^identifier:/ {
      if (index($0, "io.github.cmy-hhxx.marketsprite") \
        || index($0, "com.mingyhud.app") \
        || index($0, "com.bingge.StockPet") \
        || index($0, "com.bingge.StockPetEnglish")) {
        print path
      }
      path = ""
    }
  '
}

cleanup_local_apps() {
  while IFS= read -r registered_path; do
    [[ -n "$registered_path" ]] || continue
    if [[ -e "$installed_app" && "${registered_path:A}" == "${installed_app:A}" ]]; then
      continue
    fi
    "$lsregister_path" -u "$registered_path" >/dev/null 2>&1 || true
  done < <(registered_app_paths)

  local removed_count=0
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    is_managed_app "$candidate" || continue

    if [[ "${candidate:A}" == "${installed_app:A}" ]]; then
      continue
    fi

    "$lsregister_path" -u "$candidate" >/dev/null 2>&1 || true
    rm -R -- "$candidate"
    print "Removed stale app $candidate"
    ((removed_count += 1))
  done < <(matching_apps)

  if [[ -e "$installed_app" ]] && ! is_managed_app "$installed_app"; then
    print -u2 "$installed_app has an unexpected bundle identifier; it was not modified."
    return 1
  fi

  local -a remaining_apps
  remaining_apps=()
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    is_managed_app "$candidate" || continue
    remaining_apps+=("${candidate:A}")
  done < <(matching_apps)

  if [[ -e "$installed_app" ]]; then
    if (( ${#remaining_apps} != 1 )) || [[ "${remaining_apps[1]}" != "${installed_app:A}" ]]; then
      print -u2 "Expected only $installed_app to remain, found ${#remaining_apps} managed apps."
      printf '%s\n' $remaining_apps >&2
      return 1
    fi
  elif (( ${#remaining_apps} != 0 )); then
    print -u2 "Expected no managed apps before installation, found ${#remaining_apps}."
    printf '%s\n' $remaining_apps >&2
    return 1
  fi

  "$lsregister_path" -gc >/dev/null 2>&1 || true

  while IFS= read -r registered_path; do
    [[ -n "$registered_path" ]] || continue
    if [[ "${registered_path:A}" != "${installed_app:A}" || ! -e "$installed_app" ]]; then
      print -u2 "Stale managed Launch Services record remains: $registered_path"
      return 1
    fi
  done < <(registered_app_paths)

  print "Managed app cleanup complete; removed $removed_count stale app(s)."
}

case "$mode" in
  cleanup)
    cleanup_local_apps
    exit 0
    ;;
  standard)
    scheme="MarketSprite"
    destination="platform=macOS,arch=arm64"
    derived_data="$root_dir/build/MarketSpriteTestDerivedData"
    ;;
  performance)
    scheme="MarketSpritePerformance"
    destination="platform=macOS"
    derived_data="$root_dir/build/MarketSpritePerformanceTestDerivedData"
    ;;
  *)
    print -u2 "Usage: $0 [standard|performance|cleanup]"
    exit 2
    ;;
esac

cleanup() {
  local test_status=$?
  local cleanup_status

  if cleanup_local_apps; then
    cleanup_status=0
  else
    cleanup_status=$?
  fi

  if (( test_status != 0 )); then
    exit "$test_status"
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT

cd "$root_dir"
Scripts/verify_architecture.sh
mise exec -- xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project MarketSprite.xcodeproj \
  -scheme "$scheme" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO
