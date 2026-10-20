#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release FoldoutSelfCheck
swift build -c release --arch arm64 --arch x86_64 --product Foldout
swift build -c release --arch arm64 --arch x86_64 --product FoldoutPreview
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/Foldout.app
appex="$app/Contents/PlugIns/FoldoutPreview.appex"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$appex/Contents/MacOS"
cp "$bin/Foldout" "$app/Contents/MacOS/Foldout"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$bin/FoldoutPreview" "$appex/Contents/MacOS/FoldoutPreview"
cp Resources/Preview-Info.plist "$appex/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/Preview.entitlements "$appex"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Foldout"' >/dev/null 2>&1 || true
  pkill -f FoldoutPreview.appex >/dev/null 2>&1 || true
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [[ -d /Applications/Foldout.app ]] && "$lsregister" -u /Applications/Foldout.app >/dev/null 2>&1 || true
  rm -rf /Applications/Foldout.app
  cp -R "$app" /Applications/
  "$lsregister" -f -R /Applications/Foldout.app
  for _ in 1 2 3 4 5; do
    pluginkit -a /Applications/Foldout.app/Contents/PlugIns/FoldoutPreview.appex
    pluginkit -e use -i com.adityarajsingh.Foldout.Preview
    sleep 1
    pluginkit -m -i com.adityarajsingh.Foldout.Preview | grep -q '^+' && break
  done
  qlmanage -r >/dev/null
  echo "Installed /Applications/Foldout.app"
fi

if [[ "${1:-}" == "--release" ]]; then
  rm -f build/Foldout.zip build/Foldout.dmg
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" build/Foldout.zip
  staging=$(mktemp -d)
  cp -R "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  hdiutil create -volname Foldout -srcfolder "$staging" -fs HFS+ -format UDZO -ov build/Foldout.dmg >/dev/null
  rm -rf "$staging"
  echo "Packaged build/Foldout.zip and build/Foldout.dmg"
fi
