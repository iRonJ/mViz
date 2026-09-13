#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d /tmp/mViz-audio-checks.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
cp Tests/BandAnalyzerChecks.swift "$work_dir/main.swift"
xcrun swiftc -module-cache-path /tmp/mViz-swift-cache mViz/Audio/BandAnalyzer.swift "$work_dir/main.swift" -o "$work_dir/checks"
"$work_dir/checks"
