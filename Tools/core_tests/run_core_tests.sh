#!/bin/sh
# Compiles the Foundation layer of RodentLimb for iPhone (shared Analysis/Data/Pose files, the iOS
# SessionStore and the iOS-only data files) with small stand-ins for the few UIKit / Combine symbols
# the store uses, and runs the end-to-end tests in CoreTests.swift: tasks, import with groups and
# models, processing with a synthetic pose, QC and decisions, group results, task export, Recently
# Deleted and restore, Move to Task, backups, legacy 1.3 studies, lookups, file-name parsing.
# Works on macOS with the Xcode command-line tools, or on Linux with a Swift 5.10+ toolchain.
# The tests use a throw-away library in the temporary folder, never ~/Documents/RodentLimb.
#   sh Tools/core_tests/run_core_tests.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../../RodentLimb"
B="${TMPDIR:-/tmp}/rodentlimb-ios-core-tests"
rm -rf "$B" && mkdir -p "$B/src"
cp "$R"/Analysis/*.swift "$R/App/L10n.swift" "$B/src/"
for f in Recording Experiment PoseStorage Exporter StudyExport Coders RecordingSidecar LibrarySafety ParameterPresets \
         Tasks TaskStats TaskExport ExportFixes ImportNaming TempFiles; do cp "$R/Data/$f.swift" "$B/src/"; done
cp "$R/Pose/PoseModels.swift" "$B/src/"
# CoreGraphics / UIKit / SwiftUI / AVFoundation are not available on Linux.
sed 's/^import CoreGraphics$//' "$R/Pose/PoseTypes.swift" > "$B/src/PoseTypes.swift"
sed 's/^import CoreGraphics$//' "$R/Data/Session.swift" > "$B/src/Session.swift"
sed -e 's/^import AVFoundation$//' -e 's/^import SwiftUI$//' -e 's/^import UIKit$//' "$R/Data/SessionStore.swift" > "$B/src/SessionStore.swift"
cp "$HERE/LinuxStubs.swift" "$HERE/CoreTests.swift" "$B/src/"
if [ "$(uname)" = "Darwin" ]; then
  # Combine and the URL security-scope methods exist on macOS: keep only the UIKit stand-ins.
  sed -e '/^protocol ObservableObject/d' -e '/^@propertyWrapper struct Published/,/^}/d' \
      -e '/^extension URL {/,/^}/d' "$HERE/LinuxStubs.swift" > "$B/src/LinuxStubs.swift"
  sed -e 's/^import AVFoundation$//' -e 's/^import SwiftUI$/import Combine/' -e 's/^import UIKit$//' \
      "$R/Data/SessionStore.swift" > "$B/src/SessionStore.swift"
fi
swiftc -O -swift-version 5 -parse-as-library "$B"/src/*.swift -o "$B/run"
"$B/run" "$@"
