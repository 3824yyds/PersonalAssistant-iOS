#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/generate_project.py
if [ ! -f NativeBuild/iphoneos/lib/libllama.a ]; then bash Scripts/build-native.sh; fi
mkdir -p build
xcodebuild -project PersonalAssistant.xcodeproj -scheme PersonalAssistant \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' build > build/device-build.log 2>&1 || { tail -n 100 build/device-build.log; exit 1; }
app=build/DerivedData/Build/Products/Release-iphoneos/PersonalAssistant.app
test -f "$app/PersonalAssistant"
cp App/Resources/OpenSourceLicenses.txt "$app/OpenSourceLicenses.txt"
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
find build/ipa -name '*.dSYM' -type d -prune -exec rm -rf '{}' \;
(cd build/ipa && /usr/bin/zip -qry ../PersonalAssistant-iOS-3.5.1-build4-unsigned.ipa Payload)
python3 Scripts/verify_ipa.py build/PersonalAssistant-iOS-3.5.1-build4-unsigned.ipa
shasum -a 256 build/PersonalAssistant-iOS-3.5.1-build4-unsigned.ipa > build/SHA256SUMS.txt
