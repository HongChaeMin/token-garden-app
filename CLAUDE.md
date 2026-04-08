# Token Garden

macOS 메뉴바 앱. Claude Code / Codex 토큰 사용량을 잔디 히트맵으로 시각화.

## Tech Stack

- Swift 6, SwiftUI, SwiftData, macOS 14+
- `xcodebuild`로 빌드 (`swift build` 사용 불가 — SwiftData 매크로 이슈)
- Claude Code: `~/.claude/` JSONL 로그 파싱 (FSEventStream)
- Codex: `~/.codex/state_5.sqlite` SQLite 폴링 (30s 주기, READONLY|NOMUTEX)

## Deploy

배포 시 반드시 `DEPLOY.md`를 참고할 것. 특히:

- **ad-hoc sign 필수** — 바이너리 교체 후 `codesign --force --sign -` 빼먹으면 설치 불가
- **릴리즈 assets에 설치 가이드 이미지 첨부** — `images/token-garden-drag.png` (드래그 → Applications)
- **릴리즈 대상 repo**: `HongChaeMin/token-garden-app` (`hongchaemin` remote로 push)
- DMG는 `build/dmg_rw.dmg`에서 앱만 교체 — 새로 만들지 말 것 (배경/아이콘 배치 유지)
- `gh release create` 전 `unset GITHUB_TOKEN` 필수 — 미해제 시 다른 계정으로 릴리즈됨

## SwiftData 주의

- 새 필드 추가 시 반드시 inline 기본값 지정: `var foo: String = "default"`
- `init`의 기본값은 마이그레이션에 적용되지 않음 — 미지정 시 스토어 리셋으로 데이터 소실
