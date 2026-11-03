#!/usr/bin/env bash
# encode-all.sh — encode the home-page recordings in the list below with one command.
#
#   tools/homepage/encode-all.sh
#
# Each line of the list is
#   source-file   output-name   [options for encode.sh, e.g. --start 1 --dur 12 --thumb 5]
# A leading ~ means your home folder. Missing source files are skipped. The output names must
# match the "file" entries of CLIPS in tools/homepage/build_home.py.
# Writes docs/public/videos/NAME.mp4, NAME.jpg and NAME-thumb.jpg. Needs ffmpeg (brew install ffmpeg).

set -euo pipefail
ENC="$(cd "$(dirname "$0")" && pwd)/encode.sh"
OUT="$(cd "$(dirname "$0")/../../docs/public" && pwd)/videos"

n=0
while read -r file name opts; do
  case "$file" in ""|\#*) continue;; esac
  case "$file" in "~/"*) file="$HOME/${file#\~/}";; esac
  if [ ! -f "$file" ]; then echo "skip: $file not found" >&2; continue; fi
  # shellcheck disable=SC2086
  bash "$ENC" "$file" "$name" $opts < /dev/null
  n=$((n+1))
done <<'LIST'
# Mac screen recordings (landscape)
~/Desktop/MAC_natrual_light.mov       mac-room-light
~/Desktop/MAC_infrare_light.mov       mac-near-infrared
# iPhone screen recordings (portrait)
~/Downloads/iOS_natural_light.mp4     iphone-room-light
~/Downloads/ios_infrare_light.mp4     iphone-near-infrared
LIST

echo "Done: $n clip(s) in $OUT"
du -ch "$OUT"/*.mp4 2>/dev/null | tail -1 || true
