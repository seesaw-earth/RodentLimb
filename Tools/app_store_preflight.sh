#!/bin/sh
# app_store_preflight.sh — run on the Mac before an App Store / TestFlight upload.
#
#   sh tools/app_store_preflight.sh                       # 1. before archiving: clean and check the project
#   sh tools/app_store_preflight.sh <archive|app|pkg>     # 2. after archiving: check what will be uploaded
#
# Step 1 removes the com.apple.quarantine attribute (and other extended attributes) from every file of
# the project, deletes Finder litter, and checks version numbers, Info.plist keys, the privacy manifest
# and (Mac) the App Sandbox entitlement.
# Step 2 checks a .xcarchive (Xcode › Organizer › right-click › Show in Finder), a .app, or an exported
# .pkg: no file with com.apple.quarantine (ITMS-91109; removed from an archive or app if found), valid
# signature, version numbers, privacy manifest.
#
# Why: a project unpacked from a downloaded zip has com.apple.quarantine on every file, and Xcode copies
# it into the app (e.g. the Core ML model weights). App Store Connect then rejects the Mac build with
# "ITMS-91109: Invalid package contents". The project also removes the attributes in its last build
# phase ("Remove Extended Attributes"); this script cleans the source and confirms the result.
#
# Uses only tools that come with macOS and Xcode (xattr, plutil, PlistBuddy, codesign, pkgutil).

set -u
# Split command output on newlines only: project paths may contain spaces.
IFS='
'
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PB=/usr/libexec/PlistBuddy
fails=0
warns=0

ok()   { printf '  ok     %s\n' "$1"; }
warn() { printf '  WARN   %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  FAIL   %s\n' "$1"; fails=$((fails + 1)); }

quarantined() {   # number of files under $1 that still carry com.apple.quarantine
  /usr/bin/xattr -r "$1" 2>/dev/null | /usr/bin/grep -c "com.apple.quarantine" | tr -d ' '
}

# ---------------------------------------------------------------------------------------------------
# 1. The project
# ---------------------------------------------------------------------------------------------------
# The project nearest to the top (in the public repository the iPhone project is at the top and the
# Mac project in Mac/; each copy of this script checks its own app).
PROJ="$(find "$ROOT" -maxdepth 3 -name '*.xcodeproj' -not -path '*/build/*' -not -path '*/node_modules/*' \
  | awk '{ print gsub("/", "/"), $0 }' | sort -n | head -n 1 | cut -d' ' -f2-)"
if [ -z "$PROJ" ]; then
  echo "No .xcodeproj found under $ROOT"; exit 1
fi
PBX="$PROJ/project.pbxproj"
# Files of the other app (the Mac app inside the iPhone repository) are not this app's files.
SKIP="/nonexistent/*"
[ "$(dirname "$PROJ")" = "$ROOT" ] && [ -d "$ROOT/Mac" ] && SKIP="$ROOT/Mac/*"
echo "Project: $PROJ"
echo
echo "Extended attributes"
before="$(quarantined "$ROOT")"
/usr/bin/xattr -cr "$ROOT" 2>/dev/null
after="$(quarantined "$ROOT")"
if [ "$after" = "0" ]; then
  ok "com.apple.quarantine removed from the project ($before file(s) had it)"
else
  fail "$after file(s) still carry com.apple.quarantine — run: sudo xattr -cr \"$ROOT\""
fi
litter="$(find "$ROOT" \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
find "$ROOT" \( -name '.DS_Store' -o -name '._*' \) -type f -not -path '*/.git/*' -delete 2>/dev/null
find "$ROOT" -name '__MACOSX' -type d -prune -exec rm -rf {} + 2>/dev/null
ok "Finder litter removed (.DS_Store, ._*, __MACOSX: $litter)"

echo
echo "Version numbers"
mv="$(grep -E '^[[:space:]]*MARKETING_VERSION = ' "$PBX" | sed -E 's/.*= ([^;]*);/\1/' | sort -u)"
bv="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBX" | sed -E 's/.*= ([^;]*);/\1/' | sort -u)"
if [ "$(printf '%s\n' "$mv" | wc -l | tr -d ' ')" = "1" ] && printf '%s' "$mv" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  ok "version $mv (CFBundleShortVersionString) — the same in Debug and Release"
else
  fail "MARKETING_VERSION differs between configurations or is not N.N.N: $(echo $mv)"
fi
if [ "$(printf '%s\n' "$bv" | wc -l | tr -d ' ')" = "1" ] && printf '%s' "$bv" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  ok "build $bv (CFBundleVersion) — must be higher than every build of this app already uploaded"
else
  fail "CURRENT_PROJECT_VERSION differs between configurations or is not numeric: $(echo $bv)"
fi

echo
echo "Settings"
if grep -q 'SDKROOT = macosx' "$PBX"; then PLATFORM=mac; else PLATFORM=ios; fi
grep -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO' "$PBX" \
  && ok "export compliance answered in Info.plist (ITSAppUsesNonExemptEncryption = NO)" \
  || warn "ITSAppUsesNonExemptEncryption not set: App Store Connect asks about encryption for every build"
if [ "$PLATFORM" = mac ]; then
  grep -q 'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category' "$PBX" \
    && ok "LSApplicationCategoryType set (required for the Mac App Store)" \
    || fail "LSApplicationCategoryType missing (the Mac App Store rejects the build)"
fi
grep -q 'Remove Extended Attributes' "$PBX" \
  && ok "build phase \"Remove Extended Attributes\" present" \
  || warn "build phase \"Remove Extended Attributes\" missing"
grep -q 'ENABLE_USER_SCRIPT_SANDBOXING = NO' "$PBX" \
  && ok "user script sandboxing off for the app target (the phase may change the built app)" \
  || warn "user script sandboxing is on: the \"Remove Extended Attributes\" phase cannot change the app"

echo
echo "Files"
for f in $(find "$ROOT" -name 'PrivacyInfo.xcprivacy' -not -path '*/build/*' -not -path "$SKIP" -not -path '*/node_modules/*'); do
  /usr/bin/plutil -lint "$f" >/dev/null 2>&1 && ok "privacy manifest valid: ${f#$ROOT/}" || fail "privacy manifest invalid: ${f#$ROOT/}"
done
[ -n "$(find "$ROOT" -name 'PrivacyInfo.xcprivacy' -not -path '*/build/*' -not -path "$SKIP" -not -path '*/node_modules/*')" ] || fail "no PrivacyInfo.xcprivacy in the project"
for f in $(find "$ROOT" -name '*.entitlements' -not -path '*/build/*' -not -path "$SKIP" -not -path '*/node_modules/*'); do
  if /usr/bin/plutil -lint "$f" >/dev/null 2>&1; then ok "entitlements valid: ${f#$ROOT/}"; else fail "entitlements invalid: ${f#$ROOT/}"; fi
  if [ "$PLATFORM" = mac ]; then
    [ "$($PB -c 'Print :com.apple.security.app-sandbox' "$f" 2>/dev/null)" = "true" ] \
      && ok "App Sandbox on (required for the Mac App Store)" || fail "App Sandbox entitlement missing in ${f#$ROOT/}"
  fi
done
for f in $(find "$ROOT" -name 'InfoPlist.strings' -not -path '*/build/*' -not -path "$SKIP" -not -path '*/node_modules/*'); do
  /usr/bin/plutil -lint "$f" >/dev/null 2>&1 || fail "invalid strings file: ${f#$ROOT/}"
done
for f in $(find "$ROOT" -path '*AppIcon.appiconset/*.png' -not -path "$SKIP" -not -path '*/node_modules/*'); do
  [ -s "$f" ] || fail "empty icon: ${f#$ROOT/}"
done
ok "app icons present"

# ---------------------------------------------------------------------------------------------------
# 2. What will be uploaded (optional argument)
# ---------------------------------------------------------------------------------------------------
check_app() {   # $1 = .app
  APP="$1"
  echo
  echo "Built app: $APP"
  n="$(quarantined "$APP")"
  if [ "$n" = "0" ]; then
    ok "no file with com.apple.quarantine (ITMS-91109)"
  elif [ "${2:-}" = fix ]; then
    # An archive or app can be cleaned in place: the attribute is not part of the code signature, and
    # Xcode signs the app again when it is distributed from the Organizer.
    /usr/bin/xattr -cr "$APP" 2>/dev/null
    left="$(quarantined "$APP")"
    [ "$left" = "0" ] && ok "com.apple.quarantine removed from $n file(s) of the app — distribute this archive again" \
      || fail "$left file(s) still carry com.apple.quarantine — run: sudo xattr -cr \"$APP\""
  else
    fail "$n file(s) with com.apple.quarantine — e.g. $(/usr/bin/xattr -r "$APP" 2>/dev/null | grep com.apple.quarantine | head -n 1). Archive again after step 1."
  fi
  if [ -f "$APP/Contents/Info.plist" ]; then INFO="$APP/Contents/Info.plist"; RES="$APP/Contents/Resources"; else INFO="$APP/Info.plist"; RES="$APP"; fi
  av="$($PB -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null)"
  ab="$($PB -c 'Print :CFBundleVersion' "$INFO" 2>/dev/null)"
  ok "Info.plist: version $av, build $ab, $($PB -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null)"
  [ -f "$RES/PrivacyInfo.xcprivacy" ] && ok "privacy manifest inside the app" || fail "PrivacyInfo.xcprivacy is not inside the app"
  ls "$RES"/*.mlmodelc >/dev/null 2>&1 && ok "Core ML models compiled into the app: $(cd "$RES" && ls -d *.mlmodelc | tr '\n' ' ')" \
    || warn "no compiled Core ML model (.mlmodelc) inside the app"
  if /usr/bin/codesign --verify --deep --strict "$APP" 2>/dev/null; then ok "signature valid"; else fail "signature invalid: codesign --verify --deep --strict --verbose=2 \"$APP\""; fi
  if [ -f "$APP/Contents/Info.plist" ]; then
    /usr/bin/codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'com.apple.security.app-sandbox' \
      && ok "signed with the App Sandbox entitlement" || fail "the signed app has no App Sandbox entitlement"
  fi
  junk="$(find "$APP" \( -name '.DS_Store' -o -name '._*' -o -name '*.md' -o -name '*.swift' \) | head -n 3)"
  [ -z "$junk" ] && ok "no stray files (.DS_Store, ._*, sources, notes)" || warn "stray files in the app: $junk"
}

if [ $# -ge 1 ]; then
  T="$1"
  case "$T" in
    *.xcarchive|*.xcarchive/)
      for a in "$T"/Products/Applications/*.app; do [ -d "$a" ] && check_app "$a" fix; done ;;
    *.app|*.app/)
      check_app "$T" fix ;;
    *.pkg)
      TMP="$(mktemp -d)"
      if /usr/sbin/pkgutil --expand-full "$T" "$TMP/x" >/dev/null 2>&1; then
        for a in $(find "$TMP/x" -maxdepth 4 -name '*.app' -type d); do check_app "$a"; done
      else
        fail "could not expand $T"
      fi
      rm -rf "$TMP" ;;
    *) echo "Give a .xcarchive, .app or .pkg"; exit 2 ;;
  esac
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "PREFLIGHT PASSED ($warns warning(s))"
else
  echo "PREFLIGHT FAILED: $fails problem(s), $warns warning(s)"
fi
[ "$fails" -eq 0 ]
