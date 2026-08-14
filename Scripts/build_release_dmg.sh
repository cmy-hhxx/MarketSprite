#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
build_dir="$root_dir/build"
derived_data="$build_dir/MarketSpriteRelease"
source_packages="$build_dir/SourcePackages"
product_dir="$derived_data/Build/Products/Release"
dist_dir="$build_dir/Dist"
dmg_assets="$root_dir/Distribution/DMG"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

version=$(mise exec -- yq -r '.settings.base.MARKETING_VERSION' "$root_dir/project.yml")
build_number=$(mise exec -- yq -r '.settings.base.CURRENT_PROJECT_VERSION' "$root_dir/project.yml")
dmg_path="$dist_dir/MarketSprite-$version.dmg"
temporary_dmg="$dist_dir/.MarketSprite-$version-$$.dmg"
mkdir -p "$build_dir" "$dist_dir"
touch "$build_dir/.metadata_never_index"
package_dir=$(mktemp -d "$build_dir/MarketSpritePackaging.XXXXXX")
packaged_app="$package_dir/MarketSprite.app"
mount_dir=""

cleanup() {
  if [[ -n "$mount_dir" ]]; then
    "$lsregister_path" -u "$mount_dir/MarketSprite.app" >/dev/null 2>&1 || true
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  fi
  if [[ -d "$package_dir" ]]; then
    "$lsregister_path" -u "$packaged_app" >/dev/null 2>&1 || true
    rm -R "$package_dir" >/dev/null 2>&1 || true
  fi
  if [[ -f "$temporary_dmg" ]]; then
    rm "$temporary_dmg" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$root_dir"

Scripts/verify_architecture.sh
mise exec -- xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project MarketSprite.xcodeproj \
  -scheme MarketSprite \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$source_packages" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='arm64 x86_64' \
  CODE_SIGNING_ALLOWED=NO

actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$product_dir/MarketSprite.app/Contents/Info.plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$product_dir/MarketSprite.app/Contents/Info.plist")
if [[ "$actual_version" != "$version" || "$actual_build" != "$build_number" ]]; then
  print -u2 "Built app version $actual_version ($actual_build) does not match project.yml $version ($build_number)."
  exit 1
fi

ditto "$product_dir/MarketSprite.app" "$packaged_app"
codesign --force --sign - --timestamp=none "$packaged_app"
codesign --verify --deep --strict --verbose=2 "$packaged_app"

mise exec -- uvx --from dmgbuild==1.6.7 dmgbuild \
  -s "$dmg_assets/settings.py" \
  -D "app=$packaged_app" \
  -D "background=$dmg_assets/background.png" \
  "MarketSprite" \
  "$temporary_dmg"

mv -f "$temporary_dmg" "$dmg_path"
hdiutil verify "$dmg_path"

mount_dir=$(mktemp -d "$build_dir/MarketSpriteMount.XXXXXX")
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null
codesign --verify --deep --strict --verbose=2 "$mount_dir/MarketSprite.app"
if [[ "$(readlink "$mount_dir/Applications")" != "/Applications" ]]; then
  print -u2 "Applications link does not target /Applications."
  exit 1
fi

packaged_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount_dir/MarketSprite.app/Contents/Info.plist")
packaged_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mount_dir/MarketSprite.app/Contents/Info.plist")
packaged_archs=$(lipo -archs "$mount_dir/MarketSprite.app/Contents/MacOS/MarketSprite")
if [[ "$packaged_version" != "$version" || "$packaged_build" != "$build_number" ]]; then
  print -u2 "Packaged app version $packaged_version ($packaged_build) does not match project.yml $version ($build_number)."
  exit 1
fi
if [[ "$packaged_archs" != *arm64* || "$packaged_archs" != *x86_64* ]]; then
  print -u2 "Packaged app is not Universal: $packaged_archs"
  exit 1
fi
"$lsregister_path" -u "$mount_dir/MarketSprite.app" >/dev/null 2>&1 || true
hdiutil detach "$mount_dir" >/dev/null
rmdir "$mount_dir"
mount_dir=""

print "Created $dmg_path"
shasum -a 256 "$dmg_path"
