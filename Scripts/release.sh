#!/usr/bin/env bash
#
# Builds, Developer ID-signs, notarizes and staples Feed Me, Seymour!, then
# packages it as FeedMeSeymour-<version>.dmg at the repo root.
#
# Requires:
#   - The "Developer ID Application: Matthew Silas (CG3Q63736Q)" certificate in
#     the login keychain.
#   - Notarization credentials in the "studio-notary" keychain profile, shared
#     with the studio apps. Set up once:
#       xcrun notarytool store-credentials "studio-notary" \
#           --apple-id "you@example.com" --team-id "CG3Q63736Q"
#   - A *Developer ID* provisioning profile for the app's bundle identifier that
#     includes its iCloud container. See "iCloud" below — this is the one piece
#     that can't be conjured from the command line, and the preflight stops here
#     if it's missing.
#
# iCloud
#   Sync is the reason this script signs manually instead of letting Xcode pick.
#   A Developer ID build that talks to CloudKit needs three things to line up:
#
#     1. An embedded Developer ID provisioning profile carrying the
#        iCloud.<bundle-id> container. Development profiles won't do — they're
#        rejected once the app is signed for distribution.
#     2. aps-environment = production in the entitlements. The checked-in
#        FeedMeSeymour.entitlements says "development" because that's right for
#        daily work, so the release entitlements are generated here instead of
#        editing the file every release.
#     3. iCloudContainerEnvironment = Production at export, or the shipped app
#        reads the development CloudKit database, which is empty for everyone
#        but you.
#
#   The CloudKit schema must also be deployed to Production in the CloudKit
#   console. Nothing here can check that, and the symptom is a build that
#   notarizes, launches, and silently syncs nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="FeedMeSeymour"
SCHEME="FeedMeSeymour"
TEAM_ID="CG3Q63736Q"
IDENTITY="Developer ID Application: Matthew Silas (${TEAM_ID})"
NOTARY_PROFILE="studio-notary"
VOLUME_NAME="Feed Me Seymour"
PROFILE_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"

BUNDLE_ID="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${SCHEME}" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')"
[ -n "${BUNDLE_ID}" ] || { echo "Couldn't read the bundle identifier from the project." >&2; exit 1; }
CONTAINER="iCloud.${BUNDLE_ID}"

die() { echo "" >&2; echo "$@" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

echo "==> Preflight for ${BUNDLE_ID}"

security find-identity -v -p codesigning | grep -qF "${IDENTITY}" \
    || die "Missing signing certificate: ${IDENTITY}
Install it from developer.apple.com/account/resources/certificates."
echo "    certificate ....... ${IDENTITY}"

xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
    || die "The \"${NOTARY_PROFILE}\" notary keychain profile is missing or rejected.
Create it with:
  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\
      --apple-id \"you@example.com\" --team-id \"${TEAM_ID}\""
echo "    notary profile .... ${NOTARY_PROFILE}"

# Find a Developer ID profile for this bundle id that carries the container.
# Xcode names these "Mac Team Direct Provisioning Profile: <bundle id>", but the
# name isn't load-bearing — what matters is the app identifier, a production APS
# environment (which is what distinguishes a distribution profile from a
# development one) and the container itself.
PROFILE_UUID=""
PROFILE_NAME=""
while IFS= read -r -d '' profile; do
    plist="$(mktemp)"
    security cms -D -i "${profile}" >"${plist}" 2>/dev/null || { rm -f "${plist}"; continue; }

    app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "${plist}" 2>/dev/null || true)"
    aps="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.aps-environment' "${plist}" 2>/dev/null || true)"
    containers="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' "${plist}" 2>/dev/null || true)"

    if [ "${app_id}" = "${TEAM_ID}.${BUNDLE_ID}" ] \
       && [ "${aps}" = "production" ] \
       && grep -qF "${CONTAINER}" <<<"${containers}"; then
        PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${plist}" 2>/dev/null || true)"
        PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "${plist}" 2>/dev/null || true)"
        rm -f "${plist}"
        break
    fi
    rm -f "${plist}"
done < <(find "${PROFILE_DIR}" -name '*.provisionprofile' -print0 2>/dev/null)

[ -n "${PROFILE_UUID}" ] || die "No Developer ID provisioning profile for ${BUNDLE_ID} with the ${CONTAINER} container.

A development profile is not enough: a Developer ID build needs a distribution
profile, and stripping iCloud to get past this would ship an app whose sync
silently does nothing.

To mint one, either:

  - Xcode: Product > Archive, then Distribute App > Direct Distribution. Xcode
    creates \"Mac Team Direct Provisioning Profile: ${BUNDLE_ID}\" and the
    next run of this script will find it. Or:

  - developer.apple.com/account/resources/profiles > + > Developer ID, pick the
    ${BUNDLE_ID} App ID, make sure iCloud is among its capabilities and
    ${CONTAINER} is selected, download it and double-click to install.

Then run this script again."

echo "    profile ........... ${PROFILE_NAME}"
echo "    iCloud container .. ${CONTAINER}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ------------------------------------------------------- release entitlements

# A copy, so the checked-in entitlements keep saying "development" for daily
# builds. $(PRODUCT_BUNDLE_IDENTIFIER) inside it still expands at build time.
ENTITLEMENTS="${WORK}/Release.entitlements"
cp "${APP_NAME}.entitlements" "${ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c "Set :aps-environment production" "${ENTITLEMENTS}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :aps-environment string production" "${ENTITLEMENTS}"

# ------------------------------------------------------------------- archive

echo "==> Archiving"
ARCHIVE="${WORK}/${APP_NAME}.xcarchive"
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE}" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_IDENTITY="${IDENTITY}" \
    PROVISIONING_PROFILE_SPECIFIER="${PROFILE_UUID}" \
    CODE_SIGN_ENTITLEMENTS="${ENTITLEMENTS}" \
    | grep -E '^\*\*|error:|warning: .*(deprecat|unused)' || true
[ -d "${ARCHIVE}" ] || die "Archive failed."

echo "==> Exporting a Developer ID build"
cat >"${WORK}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>${IDENTITY}</string>
    <!-- Without this the shipped app reads the development CloudKit database. -->
    <key>iCloudContainerEnvironment</key><string>Production</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key><string>${PROFILE_UUID}</string>
    </dict>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${WORK}/export" \
    -exportOptionsPlist "${WORK}/ExportOptions.plist" \
    | grep -E '^\*\*|error:' || true

APP="${WORK}/export/${APP_NAME}.app"
[ -d "${APP}" ] || die "Export failed — no ${APP_NAME}.app produced."

# ------------------------------------------------------------------- verify

echo "==> Verifying the signature and the iCloud entitlements"
codesign --verify --strict --verbose=2 "${APP}"
codesign -dvv "${APP}" 2>&1 | grep -q "Authority=Developer ID Application" \
    || die "The app is not Developer ID-signed."

[ -f "${APP}/Contents/embedded.provisionprofile" ] \
    || die "No embedded provisioning profile — iCloud would fail at runtime."

BUILT_ENTITLEMENTS="$(codesign -d --entitlements - --xml "${APP}" 2>/dev/null | plutil -convert xml1 -o - -)"
grep -qF "${CONTAINER}" <<<"${BUILT_ENTITLEMENTS}" \
    || die "The signed app is missing the ${CONTAINER} entitlement."
grep -A1 'aps-environment' <<<"${BUILT_ENTITLEMENTS}" | grep -q 'production' \
    || die "The signed app's aps-environment is not production."
echo "    Developer ID signed, ${CONTAINER} present, aps-environment production"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")"
DMG="${APP_NAME}-${VERSION}.dmg"

# ---------------------------------------------------------------- notarize

echo "==> Submitting to the notary service (usually a few minutes)"
ditto -c -k --keepParent "${APP}" "${WORK}/${APP_NAME}.zip"
SUBMIT_OUTPUT="$(xcrun notarytool submit "${WORK}/${APP_NAME}.zip" \
    --keychain-profile "${NOTARY_PROFILE}" --wait)"
echo "${SUBMIT_OUTPUT}"
if ! grep -q "status: Accepted" <<<"${SUBMIT_OUTPUT}"; then
    SUBMISSION_ID="$(awk '/id:/{print $2; exit}' <<<"${SUBMIT_OUTPUT}")"
    echo "Notarization failed. Log:" >&2
    xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
    exit 1
fi

# Staple the app rather than only the DMG, so it stays trusted offline even
# after someone drags it out of the disk image.
echo "==> Stapling"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

# ------------------------------------------------------------------ package

echo "==> Packaging ${DMG}"
mkdir "${WORK}/staging"
cp -R "${APP}" "${WORK}/staging/"
ln -s /Applications "${WORK}/staging/Applications"
rm -f "${DMG}"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${WORK}/staging" \
    -fs HFS+ -format UDZO -ov "${DMG}" >/dev/null

echo "==> Checking Gatekeeper"
spctl --assess --type execute --verbose "${APP}"

echo
echo "Built ${DMG}"
echo
echo "Before publishing, mount it and launch the app from inside it: notarization"
echo "only proves the bundle is signed, not that it runs — and it won't tell you"
echo "whether the CloudKit schema is deployed to Production. Sign in, add a feed,"
echo "and check it reaches another device."
