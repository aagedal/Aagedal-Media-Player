#!/usr/bin/env bash
# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build, sign, notarize, and publish a new release. After completing the build
# pipeline this script signs the resulting .zip with Sparkle's EdDSA key and
# prepends a new <item> to appcast.xml so existing installs auto-update.
#
# Prerequisites (one-time setup):
#   1. Sparkle SDK installed via SPM (it is, as of the Sparkle integration).
#   2. EdDSA keypair generated. Sparkle ships `generate_keys` with its SPM
#      checkout. After Xcode resolves dependencies once, locate it with:
#        find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f
#      then run it once — it prints the public key (paste into Info.plist as
#      SUPublicEDKey) and stores the private key in your login Keychain.
#   3. notarytool credentials stored in Keychain as the profile name below.
#   4. GitHub CLI (`gh`) installed and authenticated (or the script will skip
#      the upload step and print manual release instructions).
#
# Usage:
#   scripts/release.sh                 # uses MARKETING_VERSION from the project
#   scripts/release.sh 1.5.1 151       # override version + build number
#
set -euo pipefail

echo "==> scripts/release.sh starting"

# -----------------------------------------------------------------------------
# Toolchain resolution
# -----------------------------------------------------------------------------
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if ! xcrun --find xcodebuild >/dev/null 2>&1; then
        if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
            export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
            echo "    (auto-set DEVELOPER_DIR=$DEVELOPER_DIR — \`xcode-select -p\` pointed at CommandLineTools)"
        else
            echo "ERROR: xcodebuild not available. Run:" >&2
            echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
            echo "or export DEVELOPER_DIR to a valid Xcode install." >&2
            exit 1
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Config — edit these once after running `generate_keys` / setting up notarytool
# -----------------------------------------------------------------------------
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-AagedalMediaPlayer}"
SIGN_UPDATE_BIN="${SIGN_UPDATE_BIN:-./bin/sign_update}"   # Sparkle tool path
GITHUB_REPOSITORY="aagedal/Aagedal-Media-Player"
APPCAST="appcast.xml"

# Homebrew tap automation. Set TAP_LOCAL_PATH to a local checkout of the
# tap repo to have this script bump the cask formula automatically. Leave
# unset to skip the tap update and get manual instructions printed instead.
TAP_LOCAL_PATH="${TAP_LOCAL_PATH:-}"
TAP_CASK_NAME="aagedal-media-player"
TAP_CASK_FILE="${TAP_CASK_FILE:-Casks/$TAP_CASK_NAME.rb}"

# -----------------------------------------------------------------------------
# Resolve version / build
# -----------------------------------------------------------------------------
PROJECT="Aagedal Media Player.xcodeproj"
SCHEME="Aagedal Media Player"

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo "    Reading version from xcodebuild -showBuildSettings (takes a few seconds)…"
    BUILD_SETTINGS=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME")
fi
if [[ -n "${1:-}" ]]; then
    MARKETING_VERSION="$1"
else
    MARKETING_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION/{print $2; exit}')
fi
if [[ -n "${2:-}" ]]; then
    CURRENT_PROJECT_VERSION="$2"
else
    CURRENT_PROJECT_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION/{print $2; exit}')
fi

echo "==> Building $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"

# Fail before deleting an old build or spending time archiving if source
# metadata, appcast ordering/signatures, scheme diagnostics, or the reviewed
# ffmpeg artifact are inconsistent.
python3 scripts/release-preflight.py \
    --version "$MARKETING_VERSION" \
    --build "$CURRENT_PROJECT_VERSION"

# -----------------------------------------------------------------------------
# Build & export
# -----------------------------------------------------------------------------
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/AagedalMediaPlayer.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Inline export options — Developer ID, no provisioning profile rewriting.
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>           <string>developer-id</string>
    <key>signingStyle</key>     <string>automatic</string>
    <key>destination</key>      <string>export</string>
</dict>
</plist>
EOF

# ARCHS=arm64 ONLY_ACTIVE_ARCH=NO: keep SwiftPM dependencies from also
# compiling an x86_64 slice that the arm64-only main target would discard.
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_DIR/$SCHEME.app"
[[ -d "$APP_PATH" ]] || { echo "Build produced no .app at $APP_PATH" >&2; exit 1; }

# Confirm the exported bundle contains the requested metadata, is arm64-only,
# carries hardened-runtime Developer ID signatures, and passes strict nested
# signature verification before notarization or upload.
python3 scripts/release-preflight.py \
    --version "$MARKETING_VERSION" \
    --build "$CURRENT_PROJECT_VERSION" \
    --app "$APP_PATH"

# -----------------------------------------------------------------------------
# Notarize & staple
# -----------------------------------------------------------------------------
NOTARIZE_ZIP="$BUILD_DIR/notarize-input.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

echo "==> Submitting to notarytool (profile: $NOTARYTOOL_PROFILE)"
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# -----------------------------------------------------------------------------
# Final zip for distribution + Sparkle signature
# -----------------------------------------------------------------------------
# --norsrc --noextattr --noacl --noqtn: skip AppleDouble metadata. Without
# these flags ditto encodes xattrs as `._<name>` companion files inside the
# zip; macOS Sequoia's Archive Utility surfaces those as visible files inside
# the .app, which breaks the codesignature seal and Gatekeeper rejects the
# bundle as "damaged". Signature and notarization staple live inside the
# bundle (CodeResources + Mach-O LC), not in xattrs.
SAFE_VERSION="${MARKETING_VERSION//./-}"
RELEASE_ZIP_NAME="Aagedal_Media_Player_${SAFE_VERSION}.zip"
RELEASE_ZIP="$BUILD_DIR/$RELEASE_ZIP_NAME"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noacl --noqtn "$APP_PATH" "$RELEASE_ZIP"

ZIP_SIZE=$(/usr/bin/stat -f%z "$RELEASE_ZIP")
echo "==> Release zip: $RELEASE_ZIP ($ZIP_SIZE bytes)"

if [[ ! -x "$SIGN_UPDATE_BIN" ]]; then
    echo "ERROR: $SIGN_UPDATE_BIN not found or not executable." >&2
    exit 1
fi

ED_SIGNATURE_LINE=$("$SIGN_UPDATE_BIN" "$RELEASE_ZIP")
echo "==> Sparkle signature: $ED_SIGNATURE_LINE"

# `sign_update` prints something like:
#   sparkle:edSignature="abc..." length="12345"
ED_SIGNATURE=$(echo "$ED_SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
[[ -n "$ED_SIGNATURE" ]] || { echo "ERROR: sign_update returned no EdDSA signature." >&2; exit 1; }

DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$MARKETING_VERSION/$RELEASE_ZIP_NAME"

# -----------------------------------------------------------------------------
# Build and validate the pending appcast entry before publishing
# -----------------------------------------------------------------------------
PUB_DATE=$(date "+%a, %d %b %Y %H:%M:%S %z")

# Extract the [$MARKETING_VERSION] section of CHANGELOG.md and convert it to
# HTML for the appcast <description>. Sparkle's "What's new" panel renders
# this as HTML, so users see the real release notes in-app instead of a link.
# Fails loudly if no matching section exists — better than shipping a release
# with empty notes.
RELEASE_NOTES_HTML=$(python3 - "CHANGELOG.md" "$MARKETING_VERSION" <<'PYEOF'
import sys, pathlib, re, html

path, version = sys.argv[1], sys.argv[2]
text = pathlib.Path(path).read_text()

pattern = rf'^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)'
m = re.search(pattern, text, re.DOTALL | re.MULTILINE)
if not m:
    sys.stderr.write(f"ERROR: CHANGELOG.md has no section for [{version}]\n")
    sys.exit(1)

out, in_list = [], False
for line in m.group(1).strip().split('\n'):
    line = line.rstrip()
    if not line:
        if in_list:
            out.append('</ul>'); in_list = False
        continue
    if line.startswith('### '):
        if in_list:
            out.append('</ul>'); in_list = False
        out.append(f'<h3>{html.escape(line[4:], quote=False)}</h3>')
    elif line.startswith('- '):
        if not in_list:
            out.append('<ul>'); in_list = True
        content = html.escape(line[2:], quote=False)
        content = re.sub(r'`([^`]+)`', r'<code>\1</code>', content)
        out.append(f'<li>{content}</li>')
    else:
        if in_list:
            out.append('</ul>'); in_list = False
        out.append(f'<p>{html.escape(line, quote=False)}</p>')

if in_list:
    out.append('</ul>')

print('\n'.join(out))
PYEOF
)

NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version $MARKETING_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$CURRENT_PROJECT_VERSION</sparkle:version>
            <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                length="$ZIP_SIZE"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIGNATURE" />
            <description><![CDATA[
$RELEASE_NOTES_HTML
            ]]></description>
        </item>
EOF
)

PENDING_APPCAST="$BUILD_DIR/appcast.xml"
python3 - "$APPCAST" "$PENDING_APPCAST" "$NEW_ITEM" <<'PYEOF'
import sys, pathlib
source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
new_item = sys.argv[3]
text = source.read_text()
needle = "        <item>"
if needle not in text:
    raise SystemExit(f"Could not find an existing <item> in {source}")
text = text.replace(needle, new_item + "\n\n" + needle, 1)
destination.write_text(text)
PYEOF

python3 scripts/release-preflight.py \
    --version "$MARKETING_VERSION" \
    --build "$CURRENT_PROJECT_VERSION" \
    --state published \
    --appcast "$PENDING_APPCAST"

# -----------------------------------------------------------------------------
# Upload only after the pending feed has passed every deterministic check
# -----------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh release view "$MARKETING_VERSION" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
        echo "==> Uploading $RELEASE_ZIP_NAME to existing GitHub release $MARKETING_VERSION"
        gh release upload "$MARKETING_VERSION" "$RELEASE_ZIP" \
            --repo "$GITHUB_REPOSITORY" \
            --clobber
    else
        echo "==> Creating GitHub release $MARKETING_VERSION"
        gh release create "$MARKETING_VERSION" "$RELEASE_ZIP" \
            --repo "$GITHUB_REPOSITORY" \
            --target main \
            --title "$MARKETING_VERSION" \
            --generate-notes
    fi
else
    echo "==> GitHub CLI is unavailable or unauthenticated — skipping upload."
    echo "    1. Create release $MARKETING_VERSION at https://github.com/$GITHUB_REPOSITORY/releases/new"
    echo "    2. Attach $RELEASE_ZIP"
fi

# Publish the already-validated feed locally only after the upload succeeds (or
# after selecting the explicit manual-upload path above).
mv "$PENDING_APPCAST" "$APPCAST"

echo "==> Prepended and validated appcast entry. Review and commit:"
echo "    git diff $APPCAST"
echo "    git add $APPCAST && git commit -m \"Release $MARKETING_VERSION\" && git push"

# -----------------------------------------------------------------------------
# Update the Homebrew tap cask
# -----------------------------------------------------------------------------
SHA256=$(shasum -a 256 "$RELEASE_ZIP" | awk '{print $1}')
echo "==> SHA256 of release zip: $SHA256"

if [[ -n "$TAP_LOCAL_PATH" && -d "$TAP_LOCAL_PATH" ]]; then
    CASK_PATH="$TAP_LOCAL_PATH/$TAP_CASK_FILE"
    if [[ ! -f "$CASK_PATH" ]]; then
        echo "ERROR: cask file not found at $CASK_PATH" >&2
        echo "       Set TAP_CASK_FILE to override the path inside the tap repo." >&2
        exit 1
    fi

    echo "==> Updating cask at $CASK_PATH"
    (
        cd "$TAP_LOCAL_PATH"
        git pull --rebase --quiet
    )

    python3 - "$CASK_PATH" "$MARKETING_VERSION" "$SHA256" <<'PYEOF'
import sys, re, pathlib
path, version, sha = sys.argv[1], sys.argv[2], sys.argv[3]
src = pathlib.Path(path).read_text()
src = re.sub(r'(\bversion\s+)"[^"]*"', f'\\1"{version}"', src, count=1)
src = re.sub(r'(\bsha256\s+)"[^"]*"', f'\\1"{sha}"',     src, count=1)
pathlib.Path(path).write_text(src)
PYEOF

    (
        cd "$TAP_LOCAL_PATH"
        if git diff --quiet -- "$TAP_CASK_FILE"; then
            echo "==> Cask already at $MARKETING_VERSION ($SHA256). Nothing to commit."
        else
            git add "$TAP_CASK_FILE"
            git commit -m "$TAP_CASK_NAME $MARKETING_VERSION"
            git push
            echo "==> Tap updated and pushed."
        fi
    )
else
    cat <<EOF
==> TAP_LOCAL_PATH not set — skipping tap update. To update manually:
    cd <your tap checkout>
    # Edit $TAP_CASK_FILE:
    #   version "$MARKETING_VERSION"
    #   sha256 "$SHA256"
    git commit -am "$TAP_CASK_NAME $MARKETING_VERSION" && git push
EOF
fi
