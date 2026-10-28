#!/usr/bin/env bash
#
# build-tools — builds the host-side tools (kassios, kassios-agent,
# kassios-mutants, kassios-lint) as universal macOS binaries and zips them for a
# GitHub release. Writes dist/kassios-<version>-macos.zip and its .sha256.
#
# Usage: Scripts/build-tools.sh <version>
#
# The version must match KassiOSToolVersion.current, so `kassios version`
# reports what the release says.
set -euo pipefail

version="${1:?usage: Scripts/build-tools.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

declared="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/KassiOSTool/ToolCommand.swift)"
if [[ "$declared" != "$version" ]]; then
  echo "build-tools: KassiOSToolVersion.current is $declared, not $version" >&2
  exit 1
fi

arch=(--arch arm64 --arch x86_64)
for product in kassios kassios-agent kassios-mutants; do
  swift build -c release "${arch[@]}" --product "$product"
done
(cd Plugins && swift build -c release "${arch[@]}" --product kassios-lint)

stage="dist/kassios-$version"
rm -rf "$stage" "dist/kassios-$version-macos.zip"
mkdir -p "$stage/bin"
bin="$(swift build -c release "${arch[@]}" --show-bin-path)"
lint_bin="$(cd Plugins && swift build -c release "${arch[@]}" --show-bin-path)"
cp "$bin"/{kassios,kassios-agent,kassios-mutants} "$stage/bin/"
cp "$lint_bin/kassios-lint" "$stage/bin/"
cp LICENSE "$stage/"

for tool in "$stage"/bin/*; do
  archs="$(lipo -archs "$tool")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "build-tools: $tool is only $archs" >&2; exit 1; }
done
"$stage/bin/kassios" version

(cd dist && ditto -c -k --norsrc --noextattr --keepParent "kassios-$version" "kassios-$version-macos.zip")
shasum -a 256 "dist/kassios-$version-macos.zip" | awk '{print $1}' > "dist/kassios-$version-macos.zip.sha256"
echo "dist/kassios-$version-macos.zip  sha256 $(cat "dist/kassios-$version-macos.zip.sha256")"
