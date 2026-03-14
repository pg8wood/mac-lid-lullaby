#!/bin/zsh

set -euo pipefail

workspace_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_path="$workspace_dir/Mac Lid Lullaby.xcodeproj"
scheme_name="Mac Lid Lullaby"
derived_data_path="${DERIVED_DATA_PATH:-$workspace_dir/build/DerivedData}"
build_products_path="$derived_data_path/Build/Products/Release"
distribution_path="${DISTRIBUTION_PATH:-$workspace_dir/dist}"
source_app_bundle="$build_products_path/$scheme_name.app"
source_dsym_bundle="$build_products_path/$scheme_name.app.dSYM"
app_bundle="$distribution_path/$scheme_name.app"
dsym_bundle="$distribution_path/$scheme_name.app.dSYM"

mkdir -p "$derived_data_path" "$distribution_path"
rm -rf "$app_bundle" "$dsym_bundle"

xcodebuild \
  -project "$project_path" \
  -scheme "$scheme_name" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO \
  build

cp -R "$source_app_bundle" "$app_bundle"

if [[ -d "$source_dsym_bundle" ]]; then
  cp -R "$source_dsym_bundle" "$dsym_bundle"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app_bundle"
fi

echo "Built $app_bundle"
