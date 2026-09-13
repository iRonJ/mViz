#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d /tmp/mViz-visual-checks.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
cp Tests/VisualizerChecks.swift "$work_dir/main.swift"
xcrun swiftc -module-cache-path /tmp/mViz-swift-cache mViz/Modes/*.swift mViz/Rendering/MotionBlend.swift mViz/Rendering/AudioColor.swift mViz/Rendering/BeatPulse.swift mViz/Audio/LocalTrack.swift mViz/Audio/AudioLevelCurve.swift mViz/Audio/SpectralFluxFollower.swift mViz/Audio/RhythmBopTracker.swift mViz/Audio/BandAnalyzer.swift "$work_dir/main.swift" -o "$work_dir/checks"
"$work_dir/checks"
