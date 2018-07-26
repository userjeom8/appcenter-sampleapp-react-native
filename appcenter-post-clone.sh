#!/bin/bash

set -euo pipefail

SPOT_PLATFORM="${SPOT_PLATFORM:-""}"
SPOT_APPLICATION_ID="${SPOT_APPLICATION_ID:-""}"
SPOT_APPLICATION_ENTRY="${SPOT_APPLICATION_ENTRY:-""}"
SPOT_URL_SCHEME="${SPOT_URL_SCHEME:-""}"
SPOT_DISPLAY_NAME="${SPOT_DISPLAY_NAME:-"Spot Reporters"}"
APPCENTER_TOKEN="${APPCENTER_TOKEN:-""}"
GOOGLE_TOKEN="${GOOGLE_TOKEN:-""}"
APPCENTER_BUILD_ID="${APPCENTER_BUILD_ID:-""}"
BADGE="${BADGE:-"0"}"
BADGE_COLOR="${BADGE_COLOR:-"orange"}"
BADGE_SCALE="0.5"
APPLICATION_VERSION="1.0" # Currently hardcoded, should infer from some other source

if [ -z "${SPOT_PLATFORM}" ] || { [ "${SPOT_PLATFORM}" != "ios" ] && [ "${SPOT_PLATFORM}" != "android" ]; } ; then
  echo "SPOT_PLATFORM not set correctly, please set to either ios or android" >&2
  exit 1
fi

if [ -z "${SPOT_APPLICATION_ID}" ]; then
  echo "SPOT_APPLICATION_ID not set, please set to desired target" >&2
  exit 1
fi

if [ -z "${SPOT_APPLICATION_ENTRY}" ] || { [ "${SPOT_APPLICATION_ENTRY}" != "WorkerMain" ] && [ "${SPOT_APPLICATION_ENTRY}" != "ReporterMain" ]; } ; then
  echo "SPOT_APPLICATION_ENTRY not set, please set to WorkerMain or ReporterMain" >&2
  exit 1
fi

if [ -z "${SPOT_URL_SCHEME}" ]; then
  echo "SPOT_URL_SCHEME not set, please set to desired value" >&2
  exit 1
fi

if [ -z "${APPCENTER_TOKEN}" ]; then
  echo "APPCENTER_TOKEN is not set, please add APPCENTER_TOKEN" >&2
  exit 1
fi

if [ -z "${GOOGLE_TOKEN}" ]; then
  echo "GOOGLE_TOKEN is not set, please add GOOGLE_TOKEN" >&2
  exit 1
fi

echo "Writing entry config..." >&2
cat <<-EOTS > src/config/entry.ts
export default {
    entry_point: "${SPOT_APPLICATION_ENTRY}"
}
EOTS

echo "Writing URL scheme config..." >&2
cat <<-EOTS > src/config/url_scheme.ts
export default {
    scheme: "${SPOT_URL_SCHEME}"
}
EOTS

which bundle || gem install bundler
bundle check || bundle install
brew update
set +u
echo "Homebrew cache directory: $(brew --cache), Homebrew domain: ${HOMEBREW_BOTTLE_DOMAIN}"
set -u
brew install imagemagick librsvg

echo "Generating icons..." >&2
SPOT_PLATFORM="${SPOT_PLATFORM}" SPOT_APPLICATION_ID="${SPOT_APPLICATION_ID}" ./build-icons.rb

if [ "${SPOT_PLATFORM}" == "ios" ]; then
  if [ "${BADGE}" -eq 1 ]; then
    echo "Badging icons..." >&2
    bundle exec sh -c "cd ios/Spot && badge --shield \"${APPLICATION_VERSION}-${APPCENTER_BUILD_ID}-${BADGE_COLOR}\" --shield_scale ${BADGE_SCALE}"
  fi
  echo "Changing application id..." >&2
  sed -i '' -E -e "s/PRODUCT_BUNDLE_IDENTIFIER = .+;/PRODUCT_BUNDLE_IDENTIFIER = ${SPOT_APPLICATION_ID};/g" ios/Spot.xcodeproj/project.pbxproj
  echo "Changing display name..." >&2
  plutil -replace CFBundleDisplayName -string "${SPOT_DISPLAY_NAME}" ios/Spot/Info.plist
  echo "Changing URL scheme..." >&2
  /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 ${SPOT_URL_SCHEME}"  ios/Spot/Info.plist
  echo "Changing AppCenter token..." >&2
  plutil -replace AppSecret -string "${APPCENTER_TOKEN}" ios/Spot/AppCenter-Config.plist
  echo "Changing Google token..." >&2
  plutil -replace AppSecret -string "${GOOGLE_TOKEN}" ios/Spot/Google-Config.plist
  echo "Changing entitlements..." >&2
  plutil -replace aps-environment -string "production" ios/Spot/Spot.entitlements
  plutil -insert beta-reports-active -bool YES ios/Spot/Spot.entitlements
else
  if [ "${BADGE}" -eq 1 ]; then
    echo "Badging icons..." >&2
    bundle exec sh -c "cd android && badge --shield \"${APPLICATION_VERSION}-${APPCENTER_BUILD_ID}-${BADGE_COLOR}\" --shield_scale ${BADGE_SCALE} --glob \"/app/src/**/ic_launcher.png\""
  fi
  echo "Changing application id..." >&2
  sed -i '' -E -e "s/applicationId .+/applicationId \"${SPOT_APPLICATION_ID}\"/g" android/app/build.gradle
  echo "Changing display name..." >&2
  sed -i '' -E -e "s/<string name=\"app_name\">.+<\/string>/<string name=\"app_name\">${SPOT_DISPLAY_NAME}<\/string>/g" android/app/src/main/res/values/strings.xml
  echo "Changing URL scheme..." >&2
  sed -i '' -E -e "s/<data android:scheme=\".+\" \/>/\
                      <data android:scheme=\"${SPOT_URL_SCHEME}\" \/>/g" android/app/src/main/AndroidManifest.xml

  echo "Changing AppCenter token..." >&2
  cat <<-EOJSON > android/app/src/main/assets/appcenter-config.json
{
  "app_secret": "${APPCENTER_TOKEN}"
}
EOJSON
  echo "Changing Google token..." >&2
  sed -i '' -E -e "s/<meta-data android:name=\"com\.google\.android\.geo\.API_KEY\" android:value=\".+\" \/>/\
                      <meta-data android:name=\"com\.google\.android\.geo\.API_KEY\" android:value=\"${GOOGLE_TOKEN}\" \/>/g" android/app/src/main/AndroidManifest.xml
fi
