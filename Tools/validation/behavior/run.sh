#!/bin/bash
# Behavior-assay validation on simulated mice (no iPhone needed).
#   1. compiles the app's analysis layer (Foundation only) with a small driver,
#   2. simulates bottom-view keypoint tracks with known ground truth,
#   3. runs the four analyzers and scores them.
# macOS with Xcode command-line tools, or Linux with a Swift 5.10+ toolchain.
# Usage: Tools/validation/behavior/run.sh [--sweep]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../../../RodentLimb"
B="$HERE/build"
rm -rf "$B" && mkdir -p "$B/src"
cp "$APP"/Analysis/*.swift "$APP/App/L10n.swift" "$B/src/"
# CoreGraphics is not available on Linux; the analysis layer does not need it.
sed 's/^import CoreGraphics$//' "$APP/Pose/PoseTypes.swift" > "$B/src/PoseTypes.swift"
sed 's/^import CoreGraphics$//' "$APP/Data/Session.swift" > "$B/src/Session.swift"
cp "$HERE/swift/main.swift" "$B/src/"
swiftc -O -swift-version 5 "$B"/src/*.swift -o "$HERE/run"
cd "$HERE"
mkdir -p out
python3 behavior_sim.py out
./run out
python3 evaluate.py out
if [ "$1" == "--sweep" ]; then python3 sweep.py; fi
