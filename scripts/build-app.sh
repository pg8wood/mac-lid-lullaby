#!/bin/zsh

set -euo pipefail

workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Mac Lid Lullaby"
product_name="mac-lid-lullaby"
app_bundle="$workspace_dir/dist/$app_name.app"
build_root="${BUILD_ROOT:-$workspace_dir/.build}"
module_cache_root="${MODULE_CACHE_ROOT:-$workspace_dir/.build/module-cache}"
swiftpm_home="${SWIFTPM_HOME:-$workspace_dir/.build/swiftpm-home}"

mkdir -p "$build_root" "$module_cache_root" "$swiftpm_home"

env \
  HOME="$swiftpm_home" \
  SWIFTPM_MODULECACHE_OVERRIDE="$module_cache_root" \
  CLANG_MODULE_CACHE_PATH="$module_cache_root" \
  swift build -c release --disable-sandbox

binary_path="$(find "$workspace_dir/.build" -path "*/release/$product_name" -type f | head -n 1)"

if [[ -z "$binary_path" ]]; then
  echo "Failed to locate built binary for $product_name" >&2
  exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp "$workspace_dir/App/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$binary_path" "$app_bundle/Contents/MacOS/$product_name"
chmod +x "$app_bundle/Contents/MacOS/$product_name"
cp "$workspace_dir/Sources/Resources/sm64ds-bye.wav" "$app_bundle/Contents/Resources/sm64ds-bye.wav"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app_bundle"
fi

echo "Built $app_bundle"
