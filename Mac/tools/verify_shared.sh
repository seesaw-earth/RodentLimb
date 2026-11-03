#!/bin/sh
# Confirms that Shared/ is byte-identical to the iPhone app's sources (RodentLimb 1.4), so the Mac and
# the iPhone compute exactly the same results. Usage: sh tools/verify_shared.sh <path to the iPhone RodentLimb/RodentLimb folder>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARED="$HERE/../Shared"
IOS="${1:?path to the iPhone project's RodentLimb/RodentLimb folder}"
status=0
for f in $(cd "$SHARED" && find . -name '*.swift' | sort); do
  if cmp -s "$SHARED/$f" "$IOS/$f"; then echo "same      $f"; else echo "DIFFERENT $f"; status=1; fi
done
exit $status
