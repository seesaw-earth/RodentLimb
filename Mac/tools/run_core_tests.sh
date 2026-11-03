#!/bin/sh
# Compiles the Foundation layer of RodentLimb for Mac (Shared/ + macOS/RodentLimbMac/Core/) with a
# small driver and runs the tests: checkpoint / resume, the batch engine with a simulated pose
# runner (pause, retry, offline video, crash recovery, shutdown), file-name parsing and exports.
# Works on macOS with the Xcode command-line tools, or on Linux with a Swift 5.10+ toolchain.
#   sh tools/run_core_tests.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
B="${TMPDIR:-/tmp}/rodentlimb-core-tests"
rm -rf "$B" && mkdir -p "$B/src"
cp "$ROOT"/Shared/Analysis/*.swift "$ROOT"/Shared/App/*.swift "$ROOT"/Shared/Data/*.swift "$B/src/"
# CoreGraphics is not available on Linux; these two files only use CGPoint/CGSize from Foundation there.
for f in "$ROOT/Shared/Pose/PoseTypes.swift"; do sed 's/^import CoreGraphics$//' "$f" > "$B/src/$(basename "$f")"; done
cp "$ROOT/Shared/Pose/PoseModels.swift" "$B/src/"
sed 's/^import CoreGraphics$//' "$ROOT/Shared/Data/Session.swift" > "$B/src/Session.swift"
cp "$ROOT"/macOS/RodentLimbMac/Core/*.swift "$B/src/"
cp "$HERE"/tests/*.swift "$B/src/"
swiftc -O -swift-version 5 -parse-as-library "$B"/src/*.swift -o "$B/run"
RL_EXPORT_DIR="$B/export" "$B/run" "$@"
if command -v python3 >/dev/null 2>&1 && [ -d "$B/export" ]; then
  python3 "$HERE/tests/validate_export.py" "$B/export"
fi
