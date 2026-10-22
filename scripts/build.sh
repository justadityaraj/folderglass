#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release FolderglassSelfCheck
swift build -c release --arch arm64 --arch x86_64 --product Folderglass
swift build -c release --arch arm64 --arch x86_64 --product FolderglassPreview
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/Folderglass.app
appex="$app/Contents/PlugIns/FolderglassPreview.appex"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$appex/Contents/MacOS"
cp "$bin/Folderglass" "$app/Contents/MacOS/Folderglass"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$bin/FolderglassPreview" "$appex/Contents/MacOS/FolderglassPreview"
cp Resources/Preview-Info.plist "$appex/Contents/Info.plist"
identity="${SIGN_IDENTITY:--}"
sign=(codesign --force --sign "$identity")
[[ "$identity" != "-" ]] && sign+=(--options runtime --timestamp)
"${sign[@]}" --entitlements Resources/Preview.entitlements "$appex"
"${sign[@]}" "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Folderglass"' >/dev/null 2>&1 || true
  pkill -f FolderglassPreview.appex >/dev/null 2>&1 || true
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [[ -d /Applications/Folderglass.app ]] && "$lsregister" -u /Applications/Folderglass.app >/dev/null 2>&1 || true
  rm -rf /Applications/Folderglass.app
  cp -R "$app" /Applications/
  "$lsregister" -f -R /Applications/Folderglass.app
  for _ in 1 2 3 4 5; do
    pluginkit -a /Applications/Folderglass.app/Contents/PlugIns/FolderglassPreview.appex
    pluginkit -e use -i com.adityarajsingh.Folderglass.Preview
    sleep 1
    pluginkit -m -i com.adityarajsingh.Folderglass.Preview | grep -q '^+' && break
  done
  qlmanage -r >/dev/null
  echo "Installed /Applications/Folderglass.app"
fi

if [[ "${1:-}" == "--release" ]]; then
  rm -f build/Folderglass.zip build/Folderglass.dmg
  notarize() { xcrun notarytool submit "$1" --keychain-profile "${NOTARY_PROFILE:-folderglass}" --wait; }
  if [[ "$identity" != "-" ]]; then
    ditto -c -k --keepParent "$app" build/Folderglass.zip
    notarize build/Folderglass.zip
    xcrun stapler staple "$app"
  fi
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" build/Folderglass.zip
  staging=$(mktemp -d)
  cp -R "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname Folderglass -srcfolder "$staging" -fs HFS+ -format UDZO -ov build/Folderglass.dmg >/dev/null
  rm -rf "$staging"
  if [[ "$identity" != "-" ]]; then
    codesign --force --sign "$identity" --timestamp build/Folderglass.dmg
    notarize build/Folderglass.dmg
    xcrun stapler staple build/Folderglass.dmg
  fi
  echo "Packaged build/Folderglass.zip and build/Folderglass.dmg"
fi
