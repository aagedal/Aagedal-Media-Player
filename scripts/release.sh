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
#   4. GitHub CLI (`gh`) installed and authenticated. Publication fails closed
#      when the release target or uploaded asset cannot be verified.
#
# Usage:
#   scripts/release.sh                 # uses committed project version/build
#   scripts/release.sh 1.6.1 163       # asserts the committed values explicitly
#
set -euo pipefail

if [[ $# -gt 2 ]]; then
    echo "Usage: scripts/release.sh [MARKETING_VERSION [CURRENT_PROJECT_VERSION]]" >&2
    exit 2
fi

if ! WORKTREE_STATUS="$(git status --porcelain)"; then
    echo "ERROR: could not inspect the release checkout." >&2
    exit 2
fi
if [[ -n "$WORKTREE_STATUS" ]]; then
    echo "ERROR: release requires a clean checkout." >&2
    echo "Commit or stash every tracked and untracked change, then retry." >&2
    exit 2
fi

SOURCE_COMMIT="$(git rev-parse --verify HEAD)"
if [[ ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: could not resolve HEAD to a full lowercase commit SHA." >&2
    exit 2
fi

echo "==> scripts/release.sh starting"
echo "==> Source commit: $SOURCE_COMMIT"

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
CASK_PATH=""

verify_tap_checkout() {
    local tap_status
    [[ -d "$TAP_LOCAL_PATH" ]] || {
        echo "ERROR: TAP_LOCAL_PATH is not a directory: $TAP_LOCAL_PATH" >&2
        return 1
    }
    CASK_PATH="$TAP_LOCAL_PATH/$TAP_CASK_FILE"
    [[ -f "$CASK_PATH" ]] || {
        echo "ERROR: cask file not found at $CASK_PATH" >&2
        echo "       Set TAP_CASK_FILE to override the path inside the tap repo." >&2
        return 1
    }
    if ! tap_status=$(git -C "$TAP_LOCAL_PATH" status --porcelain); then
        echo "ERROR: could not inspect the Homebrew tap checkout at $TAP_LOCAL_PATH." >&2
        return 1
    fi
    [[ -z "$tap_status" ]] || {
        echo "ERROR: Homebrew tap checkout must be clean before automated publication." >&2
        return 1
    }
}

# A configured tap is part of the publication transaction. Reject an invalid or
# dirty checkout before spending time on the archive or mutating GitHub state.
if [[ -n "$TAP_LOCAL_PATH" ]]; then
    verify_tap_checkout
fi

# -----------------------------------------------------------------------------
# Resolve and bind version / build to committed source metadata
# -----------------------------------------------------------------------------
PROJECT="Aagedal Media Player.xcodeproj"
SCHEME="Aagedal Media Player"
RESOLVED_PACKAGES="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

echo "    Reading committed version from xcodebuild -showBuildSettings (takes a few seconds)…"
BUILD_SETTINGS=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME")
PROJECT_MARKETING_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION/{print $2; exit}')
PROJECT_BUILD_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION/{print $2; exit}')
[[ -n "$PROJECT_MARKETING_VERSION" && -n "$PROJECT_BUILD_VERSION" ]] || {
    echo "ERROR: could not read committed project version/build settings." >&2
    exit 2
}

MARKETING_VERSION="${1:-$PROJECT_MARKETING_VERSION}"
CURRENT_PROJECT_VERSION="${2:-$PROJECT_BUILD_VERSION}"
if [[ "$MARKETING_VERSION" != "$PROJECT_MARKETING_VERSION" \
   || "$CURRENT_PROJECT_VERSION" != "$PROJECT_BUILD_VERSION" ]]; then
    echo "ERROR: release version/build must match the committed project metadata." >&2
    echo "       Project: $PROJECT_MARKETING_VERSION ($PROJECT_BUILD_VERSION)" >&2
    echo "       Requested: $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)" >&2
    echo "Update and commit the Xcode project metadata before releasing." >&2
    exit 2
fi

# A release must consume the successful canonical verification for this exact
# source and dependency graph. Re-validating the retained XCTest JSON prevents
# a hand-edited status file or a newly unexpected skip from becoming evidence.
CANDIDATE_EVIDENCE_DIR="${CANDIDATE_EVIDENCE_DIR:-}"
if [[ -z "$CANDIDATE_EVIDENCE_DIR" ]]; then
    echo "ERROR: set CANDIDATE_EVIDENCE_DIR to a completed canonical verifier output." >&2
    exit 2
fi
CANDIDATE_ENVIRONMENT="$CANDIDATE_EVIDENCE_DIR/environment.txt"
CANDIDATE_SUMMARY="$CANDIDATE_EVIDENCE_DIR/test-summary.json"
CANDIDATE_DETAILS="$CANDIDATE_EVIDENCE_DIR/test-details.json"
CANDIDATE_MIXED_SUMMARY="$CANDIDATE_EVIDENCE_DIR/mixed-backend-transport-summary.json"
CANDIDATE_MIXED_DETAILS="$CANDIDATE_EVIDENCE_DIR/mixed-backend-transport-details.json"
for required_evidence in \
    "$CANDIDATE_ENVIRONMENT" "$CANDIDATE_SUMMARY" "$CANDIDATE_DETAILS" \
    "$CANDIDATE_MIXED_SUMMARY" "$CANDIDATE_MIXED_DETAILS"; do
    if [[ ! -f "$required_evidence" ]]; then
        echo "ERROR: candidate evidence is incomplete: $required_evidence" >&2
        exit 2
    fi
done
EVIDENCE_SOURCE_COMMIT=$(awk -F= '$1 == "sourceCommit" { print $2; exit }' "$CANDIDATE_ENVIRONMENT")
EVIDENCE_PACKAGE_SHA256=$(awk -F= '$1 == "packageResolvedSHA256" { print $2; exit }' "$CANDIDATE_ENVIRONMENT")
EVIDENCE_STATUS=$(awk -F= '$1 == "status" { print $2; exit }' "$CANDIDATE_ENVIRONMENT")
CURRENT_PACKAGE_SHA256=$(shasum -a 256 "$RESOLVED_PACKAGES" | awk '{print $1}')
if [[ "$EVIDENCE_STATUS" != "passed" \
   || "$EVIDENCE_SOURCE_COMMIT" != "$SOURCE_COMMIT" \
   || "$EVIDENCE_PACKAGE_SHA256" != "$CURRENT_PACKAGE_SHA256" ]]; then
    echo "ERROR: candidate evidence does not match this completed source checkout." >&2
    echo "Run scripts/verify-release-candidate.sh again from the current clean commit." >&2
    exit 2
fi
python3 scripts/validate-release-xcresult.py \
    "$CANDIDATE_SUMMARY" "$CANDIDATE_DETAILS" --minimum-tests 683
python3 scripts/validate-release-xcresult.py \
    "$CANDIDATE_MIXED_SUMMARY" "$CANDIDATE_MIXED_DETAILS" --minimum-tests 2 \
    --exact-tests 2 \
    --require-test "CompareLiveBackendTests/testAVFoundationPrimaryAndMPVSecondaryShareTransport()" \
    --require-test "CompareLiveBackendTests/testMPVPrimaryAndAVFoundationSecondaryShareTransport()"

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
    -onlyUsePackageVersionsFromResolvedFile \
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

# Validate the artifact users will actually download, not only the exported app
# from which it was created. This catches packaging damage, a missing stapled
# ticket, and Gatekeeper rejection before signing or publishing the update.
DISTRIBUTION_CHECK_DIR="$BUILD_DIR/distribution-check"
/bin/mkdir -p "$DISTRIBUTION_CHECK_DIR"
/usr/bin/ditto -x -k "$RELEASE_ZIP" "$DISTRIBUTION_CHECK_DIR"
PACKAGED_APP_PATH="$DISTRIBUTION_CHECK_DIR/$SCHEME.app"
[[ -d "$PACKAGED_APP_PATH" ]] || {
    echo "ERROR: release zip contains no $SCHEME.app" >&2
    exit 1
}

python3 scripts/release-preflight.py \
    --version "$MARKETING_VERSION" \
    --build "$CURRENT_PROJECT_VERSION" \
    --app "$PACKAGED_APP_PATH"
xcrun stapler validate "$PACKAGED_APP_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$PACKAGED_APP_PATH"

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
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: GitHub CLI is unavailable or unauthenticated." >&2
    echo "The signed artifact and pending appcast remain in $BUILD_DIR; appcast.xml was not changed." >&2
    exit 1
fi

verify_release_identity() {
    local published_source_commit release_state release_is_draft release_is_prerelease
    published_source_commit=$(gh api \
        "repos/$GITHUB_REPOSITORY/commits/$MARKETING_VERSION" --jq .sha)
    [[ "$published_source_commit" == "$SOURCE_COMMIT" ]] || {
        echo "ERROR: GitHub release $MARKETING_VERSION targets $published_source_commit, not $SOURCE_COMMIT." >&2
        return 1
    }
    release_state=$(gh release view "$MARKETING_VERSION" \
        --repo "$GITHUB_REPOSITORY" --json isDraft,isPrerelease \
        --jq '[.isDraft, .isPrerelease] | @tsv')
    IFS=$'\t' read -r release_is_draft release_is_prerelease <<< "$release_state"
    [[ "$release_is_draft" == "false" ]] || {
        echo "ERROR: GitHub release $MARKETING_VERSION is still a draft." >&2
        return 1
    }
    [[ "$release_is_prerelease" == "false" ]] || {
        echo "ERROR: GitHub release $MARKETING_VERSION is a prerelease; refusing stable appcast publication." >&2
        return 1
    }
}

if gh release view "$MARKETING_VERSION" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    # Check before --clobber so an unrelated existing release is never mutated.
    verify_release_identity
    echo "==> Uploading $RELEASE_ZIP_NAME to existing GitHub release $MARKETING_VERSION"
    gh release upload "$MARKETING_VERSION" "$RELEASE_ZIP" \
        --repo "$GITHUB_REPOSITORY" \
        --clobber
else
    echo "==> Creating GitHub release $MARKETING_VERSION"
    gh release create "$MARKETING_VERSION" "$RELEASE_ZIP" \
        --repo "$GITHUB_REPOSITORY" \
        --target "$SOURCE_COMMIT" \
        --title "$MARKETING_VERSION" \
        --generate-notes
fi

# Recheck identity after mutation, then prove that the remote asset's name,
# byte size and GitHub-computed SHA-256 identify the exact local ZIP before
# publishing its update URL.
verify_release_identity
ZIP_SHA256=$(shasum -a 256 "$RELEASE_ZIP" | awk '{print $1}')
PUBLISHED_RELEASE_JSON="$BUILD_DIR/published-release.json"
gh api "repos/$GITHUB_REPOSITORY/releases/tags/$MARKETING_VERSION" > "$PUBLISHED_RELEASE_JSON"
python3 scripts/validate-github-release-asset.py \
    "$PUBLISHED_RELEASE_JSON" "$RELEASE_ZIP_NAME" "$ZIP_SIZE" "$ZIP_SHA256"

# Publish the already-validated feed locally only after the release target and
# exact downloadable asset have been verified.
mv "$PENDING_APPCAST" "$APPCAST"

echo "==> Prepended and validated appcast entry. Review and commit:"
echo "    git diff $APPCAST"
echo "    git add $APPCAST && git commit -m \"Release $MARKETING_VERSION\" && git push"

# -----------------------------------------------------------------------------
# Update the Homebrew tap cask
# -----------------------------------------------------------------------------
echo "==> SHA256 of release zip: $ZIP_SHA256"

if [[ -n "$TAP_LOCAL_PATH" ]]; then
    # Recheck after the long-running build/notarization/upload sequence in case
    # another process changed the tap while this release was being prepared.
    verify_tap_checkout
    echo "==> Updating cask at $CASK_PATH"
    (
        cd "$TAP_LOCAL_PATH"
        git pull --rebase --quiet
    )

    python3 scripts/update-homebrew-cask.py \
        "$CASK_PATH" "$MARKETING_VERSION" "$ZIP_SHA256"

    (
        cd "$TAP_LOCAL_PATH"
        if git diff --quiet -- "$TAP_CASK_FILE"; then
            echo "==> Cask already at $MARKETING_VERSION ($ZIP_SHA256). Nothing to commit."
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
    #   sha256 "$ZIP_SHA256"
    git commit -am "$TAP_CASK_NAME $MARKETING_VERSION" && git push
EOF
fi
