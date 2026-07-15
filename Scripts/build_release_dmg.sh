#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/sortwell-release.XXXXXX")"
ARCHIVE_PATH="${WORK_DIR}/Sortwell.xcarchive"
STAGING_DIR="${WORK_DIR}/dmg"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

xcodebuild archive \
  -project "${ROOT_DIR}/Sortwell.xcodeproj" \
  -scheme Sortwell \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM=""

APP_PATH="${ARCHIVE_PATH}/Products/Applications/Sortwell.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
DMG_NAME="Sortwell-${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

mkdir -p "${STAGING_DIR}" "${OUTPUT_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/Sortwell.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}" "${DMG_PATH}.sha256"
hdiutil create \
  -volname "Sortwell" \
  -srcfolder "${STAGING_DIR}" \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
hdiutil verify "${DMG_PATH}"
(
  cd "${OUTPUT_DIR}"
  shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

printf 'Created %s\n' "${DMG_PATH}"
printf 'Created %s\n' "${DMG_PATH}.sha256"
