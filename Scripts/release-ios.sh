#!/usr/bin/env bash
#
# Archives the iOS app, exports it for App Store Connect, and uploads it to
# TestFlight.
#
# There is no iOS equivalent of Scripts/release.sh — no Developer ID, no
# notarized download people can fetch from a website. Getting a build onto an
# iPhone that isn't plugged into this Mac means going through App Store Connect,
# and TestFlight is the short way round: internal testers (your own App Store
# Connect team, up to 100) get builds with no review at all. External testers
# need a one-time Beta App Review on the first build. Either way builds expire
# after 90 days, so this is a rolling thing rather than a permanent home.
#
# Requires:
#   - An "Apple Distribution" certificate in the login keychain. This is NOT
#     the Developer ID certificate the Mac release uses; App Store builds are
#     signed with a different kind.
#   - An App Store Connect API key (App Store Connect > Users and Access >
#     Integrations > App Store Connect API). Download the .p8 once — Apple
#     won't let you download it again — and put it at
#       ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#     then set, e.g. in your shell profile:
#       export ASC_KEY_ID=XXXXXXXXXX
#       export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#     A key is better than an app-specific password here: it's scoped, it's
#     revocable on its own, and xcodebuild can use it to create the
#     distribution profile for you.
#   - An app record in App Store Connect for the bundle identifier. Uploading
#     doesn't create one; the upload just fails if it isn't there.
#
# Build numbers
#   App Store Connect refuses a build whose (version, build) pair it has seen
#   before, so the build number is a UTC timestamp, passed on the command line.
#   The checked-in project keeps CURRENT_PROJECT_VERSION = 1 and is not touched.
#
# Usage:
#   Scripts/release-ios.sh              # archive, export, upload
#   NO_UPLOAD=1 Scripts/release-ios.sh  # stop after exporting the .ipa
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="FeedMeSeymour"
SCHEME="FeedMeSeymour"
TEAM_ID="CG3Q63736Q"

die() { echo "" >&2; echo "$@" >&2; exit 1; }

BUNDLE_ID="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" \
    -configuration Release -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null \
    | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')"
[ -n "${BUNDLE_ID}" ] || die "Couldn't read the bundle identifier from the project."

# ---------------------------------------------------------------- preflight

echo "==> Preflight for ${BUNDLE_ID} (iOS)"

IDENTITIES="$(security find-identity -v -p codesigning)"
grep -q "Apple Distribution" <<<"${IDENTITIES}" \
    || die "No \"Apple Distribution\" certificate in the login keychain.

App Store builds are signed with an Apple Distribution certificate, which is a
different kind from the Developer ID one the Mac release uses — having that one
is not enough.

Easiest route: Xcode > Settings > Accounts > your Apple ID > Manage
Certificates > + > Apple Distribution. Or create it at
developer.apple.com/account/resources/certificates and double-click to install."
echo "    certificate ....... Apple Distribution"

: "${ASC_KEY_ID:?Set ASC_KEY_ID to your App Store Connect API key id (see the notes at the top of this script)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to your App Store Connect API issuer id}"

KEY_PATH=""
for candidate in \
    "${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" \
    "${HOME}/private_keys/AuthKey_${ASC_KEY_ID}.p8" \
    "./private_keys/AuthKey_${ASC_KEY_ID}.p8"; do
    [ -f "${candidate}" ] && { KEY_PATH="${candidate}"; break; }
done
[ -n "${KEY_PATH}" ] || die "Can't find AuthKey_${ASC_KEY_ID}.p8.

Put it at ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8 — that's
where both xcodebuild and altool look for it without being told."
echo "    api key ........... ${KEY_PATH/#$HOME/~}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

VERSION="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" \
    -configuration Release -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
echo "    version ........... ${VERSION} (${BUILD_NUMBER})"

AUTH=(-authenticationKeyPath "$(cd "$(dirname "${KEY_PATH}")" && pwd)/$(basename "${KEY_PATH}")"
      -authenticationKeyID "${ASC_KEY_ID}"
      -authenticationKeyIssuerID "${ASC_ISSUER_ID}")

# ------------------------------------------------------------------- archive

echo "==> Archiving for iOS"
ARCHIVE="${WORK}/${APP_NAME}.xcarchive"
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "${ARCHIVE}" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    -allowProvisioningUpdates "${AUTH[@]}" \
    | grep -E '^\*\*|error:' || true
[ -d "${ARCHIVE}" ] || die "Archive failed."

echo "==> Exporting for App Store Connect"
cat >"${WORK}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>destination</key><string>export</string>
    <key>uploadSymbols</key><true/>
    <!-- No iCloudContainerEnvironment here: App Store builds always get the
         production CloudKit environment, and setting it is an error. -->
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${WORK}/export" \
    -exportOptionsPlist "${WORK}/ExportOptions.plist" \
    -allowProvisioningUpdates "${AUTH[@]}" \
    | grep -E '^\*\*|error:' || true

IPA="$(ls "${WORK}/export/"*.ipa 2>/dev/null | head -1 || true)"
[ -n "${IPA}" ] || die "Export failed — no .ipa produced."

# ------------------------------------------------------------------- verify

# Worth doing before the upload rather than after: App Store Connect will take
# a build with the wrong push entitlement quite happily, and the first sign of
# trouble is sync that never updates on anyone's phone.
echo "==> Verifying the exported build"
unzip -q "${IPA}" -d "${WORK}/unpacked"
PAYLOAD_APP="$(find "${WORK}/unpacked/Payload" -maxdepth 1 -name '*.app' | head -1)"
[ -n "${PAYLOAD_APP}" ] || die "No .app inside the .ipa."

ENTITLEMENTS="$(codesign -d --entitlements - --xml "${PAYLOAD_APP}" 2>/dev/null | plutil -convert xml1 -o - -)"
CONTAINER="iCloud.${BUNDLE_ID}"
grep -qF "${CONTAINER}" <<<"${ENTITLEMENTS}" \
    || die "The exported build is missing the ${CONTAINER} entitlement."
APS_LINE="$(grep -A1 '<key>aps-environment</key>' <<<"${ENTITLEMENTS}" || true)"
grep -q 'production' <<<"${APS_LINE}" \
    || die "The exported build's aps-environment is not production.
On iOS the key is spelled \"aps-environment\" (macOS uses
com.apple.developer.aps-environment); without it set to production CloudKit
never delivers a change notification to a TestFlight build."
echo "    ${CONTAINER} present, aps-environment production"

if [ "${NO_UPLOAD:-0}" = "1" ]; then
    cp "${IPA}" "${ROOT}/"
    echo ""
    echo "Exported $(basename "${IPA}") (not uploaded — NO_UPLOAD=1)"
    exit 0
fi

# -------------------------------------------------------------------- upload

echo "==> Uploading to App Store Connect (a few minutes)"
xcrun altool --upload-app --type ios --file "${IPA}" \
    --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}" \
    || die "Upload failed.

If it says the app doesn't exist, create the record first: App Store Connect >
Apps > + > New App, with bundle identifier ${BUNDLE_ID}. Uploading
never creates the record."

echo ""
echo "Uploaded ${VERSION} (${BUILD_NUMBER}) to App Store Connect."
echo ""
echo "It takes a few minutes to finish processing before TestFlight will show"
echo "it. Internal testers can install it as soon as it appears. External"
echo "testers need Beta App Review once, on the first build only."
echo ""
echo "Builds expire 90 days after upload."
