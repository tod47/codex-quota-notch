#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_root="$project_root/build/CodexQuotaNotch.app"
contents_root="$bundle_root/Contents"
release_arch="$(uname -m)"

universal_build=false
if [[ "${1:-}" == "--universal" ]]; then
    universal_build=true
fi

if $universal_build; then
    swift build -c release --arch arm64
    swift build -c release --arch x86_64
else
    swift build -c release
fi

rm -rf "$bundle_root"
mkdir -p "$contents_root/MacOS" "$contents_root/Resources"

if $universal_build; then
    arm_binary="$project_root/.build/arm64-apple-macosx/release/CodexQuotaNotch"
    intel_binary="$project_root/.build/x86_64-apple-macosx/release/CodexQuotaNotch"
    lipo -create "$arm_binary" "$intel_binary" -output "$contents_root/MacOS/CodexQuotaNotch"
    resource_root="$project_root/.build/arm64-apple-macosx/release"
else
    binary_root="$project_root/.build/${release_arch}-apple-macosx/release"
    binary_path="$binary_root/CodexQuotaNotch"
    if [[ ! -x "$binary_path" ]]; then
        binary_path="$(find "$project_root/.build" -path '*/release/CodexQuotaNotch' -type f -print -quit)"
        binary_root="$(dirname "$binary_path")"
    fi
    cp "$binary_path" "$contents_root/MacOS/CodexQuotaNotch"
    resource_root="$binary_root"
fi

resource_bundle="$(find "$resource_root" -maxdepth 1 -type d -name 'CodexQuotaNotch_*.bundle' -print -quit)"
if [[ -n "$resource_bundle" ]]; then
    cp -R "$resource_bundle" "$contents_root/Resources/"
fi

cp "$project_root/Resources/Info.plist" "$contents_root/Info.plist"
chmod +x "$contents_root/MacOS/CodexQuotaNotch"

echo "Built $bundle_root"
