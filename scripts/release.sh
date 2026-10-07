#!/usr/bin/env bash
# Builds a release of Otter (T13): a Developer ID–signed, notarized and stapled Otter.app inside a
# signed, notarized and stapled DMG, plus the Sparkle appcast and the release notes.
#
#   scripts/release.sh 0.1.1            # a real release, as CI runs it on a `v*` tag
#   scripts/release.sh --local 0.1.1    # ad-hoc signed, not notarized: for testing this script
#                                       # and Sparkle updates on this Mac only
#
# Output goes to build/release/<version>/:
#   Otter-<version>.dmg     the download (also what Sparkle installs)
#   appcast.xml             Sparkle's feed, uploaded beside the DMG
#   release-notes.md        this version's CHANGELOG.md section, for the GitHub release
#   Otter-<version>.dmg.sha256
#
# Environment (a real release):
#   DEVELOPMENT_TEAM          the Team ID that owns the Developer ID Application certificate
#   Notarization, one of:
#     NOTARY_KEYCHAIN_PROFILE a profile saved with `xcrun notarytool store-credentials`
#     ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   an App Store Connect API key (CI)
#   SPARKLE_PRIVATE_KEY       optional; without it generate_appcast uses the key in the keychain
#   SPARKLE_PUBLIC_ED_KEY     optional; overrides the project's, e.g. a throwaway key for --local
#   DOWNLOAD_URL_PREFIX       optional; where the appcast says the DMG is, e.g. http://localhost:8000/
#                             to test updates; defaults to this version's GitHub release
#   BUILD_NUMBER              optional; defaults to the commit count, so it only ever goes up
#
# Never commit certificates (.p12), API keys (.p8) or Sparkle's private key.
set -euo pipefail

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 64
}

LOCAL=false
if [[ "${1:-}" == "--local" ]]; then
    LOCAL=true
    shift
fi
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO_URL="https://github.com/elizabeth-ling/otter"
OUT="build/release/$VERSION"
ARCHIVE="$OUT/Otter.xcarchive"
APP="$OUT/export/Otter.app"
DMG="$OUT/Otter-$VERSION.dmg"
PACKAGES="build/SourcePackages"
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# This version's section of CHANGELOG.md, without its heading or surrounding blank lines.
release_notes() {
    awk -v heading="## [$VERSION]" '
        index($0, heading) == 1 { found = 1; next }
        found && /^## / { exit }
        found { lines[++n] = $0; if ($0 ~ /[^[:space:]]/) { if (!first) first = n; last = n } }
        END { for (i = first; first && i <= last; i++) print lines[i] }
    ' CHANGELOG.md
}

# Fails unless Gatekeeper accepts the file as notarized Developer ID software.
gatekeeper_accepts() {
    local type="$1" file="$2" result
    result="$(spctl -a -vv -t "$type" "$file" 2>&1 || true)"
    echo "$result"
    [[ "$result" == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper doesn't accept $(basename "$file")"
}

# Submits a file to Apple's notary service and waits; prints the log and fails unless accepted.
notarize() {
    local file="$1" auth result id status
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    else
        auth=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    fi
    result="$(xcrun notarytool submit "$file" "${auth[@]}" --wait --output-format json)"
    id="$(plutil -extract id raw - <<<"$result")"
    status="$(plutil -extract status raw - <<<"$result")"
    echo "Notarization $id: $status"
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" "${auth[@]}" || true
        fail "notarization of $(basename "$file") was not accepted"
    fi
}

# --- Checks, before anything slow ---------------------------------------------------------------

NOTES="$(release_notes)"
[[ -n "$NOTES" ]] || fail "CHANGELOG.md has no '## [$VERSION]' section"

if ! $LOCAL; then
    [[ -n "${DEVELOPMENT_TEAM:-}" ]] || fail "set DEVELOPMENT_TEAM to the Developer ID team's ID"
    if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]] && [[ -z "${ASC_KEY_PATH:-}" || -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
        fail "set NOTARY_KEYCHAIN_PROFILE, or ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID"
    fi
    # The SHA-1 of the team's Developer ID Application identity, for signing the DMG.
    IDENTITY="$(security find-identity -v -p codesigning | awk -v team="($DEVELOPMENT_TEAM)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')"
    [[ -n "$IDENTITY" ]] || fail "no Developer ID Application identity for team $DEVELOPMENT_TEAM in the keychain"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "warning: the working tree has uncommitted changes; they're in this build" >&2
    fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# --- 1. Archive and export ----------------------------------------------------------------------

step "Archiving Otter $VERSION ($BUILD_NUMBER)"
BUILD_SETTINGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    BUILD_SETTINGS+=(SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY")
fi
if $LOCAL; then
    BUILD_SETTINGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
else
    BUILD_SETTINGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp)
fi
xcodebuild archive \
    -project Otter.xcodeproj -scheme Otter -configuration Release \
    -archivePath "$ARCHIVE" \
    -clonedSourcePackagesDirPath "$PACKAGES" \
    -derivedDataPath build/DerivedData \
    "${BUILD_SETTINGS[@]}" \
    | grep -E '(error|warning):|^\*\*' || true
[[ -d "$ARCHIVE/Products/Applications/Otter.app" ]] || fail "the archive failed; run xcodebuild without the filter to see why"

if $LOCAL; then
    mkdir -p "$(dirname "$APP")"
    ditto "$ARCHIVE/Products/Applications/Otter.app" "$APP"
else
    step "Exporting with Developer ID"
    cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$DEVELOPMENT_TEAM</string>
</dict>
</plist>
EOF
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist"
fi

step "Checking the app"
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || fail "the app's version isn't $VERSION"
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" ]] \
    || fail "SPARKLE_PUBLIC_ED_KEY is empty in the project; run Sparkle's generate_keys and set it"
if ! $LOCAL; then
    SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1)"
    [[ "$SIGNATURE" =~ flags=.*runtime ]] || fail "the app isn't signed with the hardened runtime"
    [[ "$SIGNATURE" == *"TeamIdentifier=$DEVELOPMENT_TEAM"* ]] || fail "the app isn't signed by team $DEVELOPMENT_TEAM"
    [[ "$SIGNATURE" == *"Timestamp="* ]] || fail "the app's signature has no secure timestamp"
fi

# --- 2–3. Notarize and staple the app ------------------------------------------------------------

if ! $LOCAL; then
    step "Notarizing Otter.app"
    ditto -c -k --keepParent "$APP" "$OUT/Otter.zip"
    notarize "$OUT/Otter.zip"
    rm "$OUT/Otter.zip"
    xcrun stapler staple "$APP"
    gatekeeper_accepts exec "$APP"
fi

# --- 4. DMG -------------------------------------------------------------------------------------

step "Building $(basename "$DMG")"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Otter.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Otter -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

if ! $LOCAL; then
    codesign --sign "$IDENTITY" --timestamp "$DMG"
    step "Notarizing the DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"

    # --- 5. What Gatekeeper will say on a download --------------------------------------------
    step "Checking the DMG"
    codesign --verify --strict --verbose=2 "$DMG"
    gatekeeper_accepts install "$DMG"
fi

# --- Release notes and Sparkle's appcast ----------------------------------------------------------

step "Writing the appcast"
printf '%s\n' "$NOTES" >"$OUT/release-notes.md"
UPDATES="$OUT/updates"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
# Sparkle shows a Markdown file named like the archive as that update's notes.
cp "$OUT/release-notes.md" "$UPDATES/Otter-$VERSION.md"
APPCAST_ARGS=(
    --download-url-prefix "${DOWNLOAD_URL_PREFIX:-$REPO_URL/releases/download/v$VERSION/}"
    --embed-release-notes
    --link "$REPO_URL"
)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${APPCAST_ARGS[@]}" "$UPDATES"
else
    "$SPARKLE_BIN/generate_appcast" "${APPCAST_ARGS[@]}" "$UPDATES"
fi
mv "$UPDATES/appcast.xml" "$OUT/appcast.xml"
rm -rf "$UPDATES"

shasum -a 256 "$DMG" | awk '{ print $1 }' >"$DMG.sha256"

step "Done"
echo "Otter $VERSION ($BUILD_NUMBER)$($LOCAL && echo ', local: ad-hoc signed, not notarized')"
ls -1 "$OUT"
