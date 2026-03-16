# Deploy

## Prerequisites

- Xcode (`/Applications/Xcode.app`)
- `codesign`, `hdiutil` (macOS built-in)

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme TokenGarden -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData \
  -configuration Release build
```

## Package

```bash
# 1. Copy binary
cp .claude/tmp/DerivedData/Build/Products/Release/TokenGarden \
   build/TokenGarden.app/Contents/MacOS/TokenGarden

# 2. Bump version (Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y.Z" build/TokenGarden.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion N" build/TokenGarden.app/Contents/Info.plist

# 3. Ad-hoc sign
codesign --force --sign - build/TokenGarden.app

# 4. DMG — RW DMG에 앱 교체 후 read-only로 변환 (배경/아이콘 배치 유지)
hdiutil attach build/dmg_rw.dmg -readwrite -noverify
rm -rf "/Volumes/Token Garden/TokenGarden.app"
cp -R build/TokenGarden.app "/Volumes/Token Garden/TokenGarden.app"
hdiutil detach "/Volumes/Token Garden"
rm -f build/TokenGarden.dmg
hdiutil convert build/dmg_rw.dmg -format UDZO -o build/TokenGarden.dmg

# 5. Zip
cd build && rm -f TokenGarden.zip && zip -r TokenGarden.zip TokenGarden.app && cd ..
```

## Release

```bash
git add build/TokenGarden.app build/TokenGarden.dmg build/TokenGarden.zip
git commit -m "build: vX.Y.Z release artifacts"
git push origin main
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z build/TokenGarden.dmg build/TokenGarden.zip --title "vX.Y.Z" --notes "release notes"
```

## Notes

- `swift build`는 SwiftData 매크로 이슈로 사용 불가 — 반드시 `xcodebuild` 사용
- DerivedData는 `.claude/tmp/DerivedData`에 생성 (`/tmp` 사용 금지, SentinelOne EDR 정책)
- 앱 번들 구조(`Info.plist`, `Resources/AppIcon.icns`)는 `build/TokenGarden.app/Contents/`에 유지
- DMG 레이아웃(배경, 아이콘 위치)은 `build/dmg_rw.dmg`에 저장됨 — 직접 만들지 말고 RW DMG에서 앱만 교체
