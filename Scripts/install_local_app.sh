#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
bundle_identifier="io.github.cmy-hhxx.marketsprite"
installed_app="/Applications/MarketSprite.app"
version=$(mise exec -- yq -r '.settings.base.MARKETING_VERSION' "$root_dir/project.yml")
build_number=$(mise exec -- yq -r '.settings.base.CURRENT_PROJECT_VERSION' "$root_dir/project.yml")
dmg_path="$root_dir/build/Dist/MarketSprite-$version.dmg"
mount_dir=""
staged_app="/Applications/.MarketSprite.installing.$$.app"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

app_bundle_identifier() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

cleanup() {
  if [[ -n "$mount_dir" ]]; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  fi
  if [[ -d "$staged_app" ]]; then
    rm -R -- "$staged_app"
  fi
}
trap cleanup EXIT

"$root_dir/Scripts/build_release_dmg.sh"

mount_dir=$(mktemp -d "$root_dir/build/MarketSpriteInstallMount.XXXXXX")
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null
source_app="$mount_dir/MarketSprite.app"

if [[ "$(app_bundle_identifier "$source_app")" != "$bundle_identifier" ]]; then
  print -u2 "The packaged app has an unexpected bundle identifier."
  exit 1
fi

"$lsregister_path" -u "$source_app" >/dev/null 2>&1 || true

for process_name in MarketSprite MingyHUD StockPet; do
  pkill -x "$process_name" >/dev/null 2>&1 || true
done

ditto "$source_app" "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"

hdiutil detach "$mount_dir" >/dev/null
rmdir "$mount_dir"
mount_dir=""

if [[ -e "$installed_app" && "$(app_bundle_identifier "$installed_app")" != "$bundle_identifier" ]]; then
  print -u2 "$installed_app exists with an unexpected bundle identifier; refusing to replace it."
  exit 1
fi

if [[ -e "$installed_app" ]]; then
  rm -R -- "$installed_app"
fi
mv "$staged_app" "$installed_app"

"$root_dir/Scripts/test.sh" cleanup

installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_app/Contents/Info.plist")
installed_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$installed_app/Contents/Info.plist")
if [[ "$installed_version" != "$version" || "$installed_build" != "$build_number" ]]; then
  print -u2 "Installed app version $installed_version ($installed_build) does not match project.yml $version ($build_number)."
  exit 1
fi
print "Installed MarketSprite $installed_version ($installed_build) at $installed_app"
