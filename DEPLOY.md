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
git push hongchaemin main
gh release create vX.Y.Z \
  build/TokenGarden.dmg \
  build/TokenGarden.zip \
  images/token-garden-drag.png \
  --repo HongChaeMin/token-garden-app \
  --title "vX.Y.Z" \
  --notes "릴리즈 노트"
```

**릴리즈 assets 체크리스트:**
- `TokenGarden.dmg` — 설치 파일
- `TokenGarden.zip` — ZIP 대체 배포
- `token-garden-drag.png` — 설치 가이드 이미지 (드래그 → Applications)

## Notes

- `swift build`는 SwiftData 매크로 이슈로 사용 불가 — 반드시 `xcodebuild` 사용
- DerivedData는 `.claude/tmp/DerivedData`에 생성 (`/tmp` 사용 금지, SentinelOne EDR 정책)
- 앱 번들 구조(`Info.plist`, `Resources/AppIcon.icns`)는 `build/TokenGarden.app/Contents/`에 유지
- DMG 레이아웃(배경, 아이콘 위치)은 `build/dmg_rw.dmg`에 저장됨 — 직접 만들지 말고 RW DMG에서 앱만 교체
- **ad-hoc sign은 필수** — 바이너리 교체 후 `codesign`을 빼먹으면 기존 서명과 바이너리 해시가 불일치하여 macOS가 설치/실행을 차단함 (서명 없는 것보다 깨진 서명이 더 심각)
- 설치 후 처음 실행 시 Gatekeeper가 차단하면 **우클릭 → 열기** 로 실행

## DMG 배경 이미지 트러블슈팅

DMG 배경(`build/dmg_rw.dmg` 내 `.background/background.png`)이 깨지는 경우가 있다.

### 증상별 원인

1. **배경 없이 흰색만 표시**: `.background/background.png` 파일이 DMG 안에 없거나 `.DS_Store`에 배경 설정이 없음
2. **배경이 확대/잘려서 표시** (텍스트가 거대하게 보임): `.DS_Store`의 윈도우 크기와 배경 이미지 크기가 불일치. 또는 다른 볼륨에서 복사한 `.DS_Store`의 alias 참조가 깨짐
3. **정상 표시**: `.background/background.png` (540x360) + `.DS_Store` (윈도우 540x360) 가 일치

### 배경 재설정 방법

DMG 배경이 깨졌을 때는 RW DMG를 마운트하고 AppleScript로 재설정:

```bash
hdiutil attach build/dmg_rw.dmg -readwrite -noverify

osascript -e '
tell application "Finder"
    tell disk "Token Garden"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 422, 840, 782}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 64
        set background picture of viewOptions to file ".background:background.png"
        set position of item "TokenGarden.app" of container window to {150, 180}
        set position of item "Applications" of container window to {390, 180}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell'

hdiutil detach "/Volumes/Token Garden"
```

**주의:** Finder 자동화 권한 필요 (시스템 설정 > 개인정보 보호 > 자동화). Claude Code 터미널에서 `-1743` 에러 나면 `! osascript ...` 로 사용자가 직접 실행해야 함. 에러가 나도 실제로는 적용될 수 있으니 DMG 열어서 확인할 것.
