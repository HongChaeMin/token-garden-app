# Token Garden

Claude Code / Codex 토큰 사용량을 추적하는 macOS 메뉴바 앱.

`~/.claude/` 로그와 `~/.codex/state_5.sqlite`를 실시간 파싱하여 히트맵, 프로젝트별 통계, 활성 세션을 보여줍니다.

## Features

- **Heatmap** — 일별 토큰 사용량을 GitHub 스타일 히트맵으로 표시 (D/W/M/Y 뷰)
- **Stats** — 오늘/이번 주/이번 달 토큰 합계 (Claude / Codex 소스 토글)
- **Projects** — 프로젝트별 사용량 및 비율
- **Active Sessions** — 현재 실행 중인 Claude / Codex 세션 실시간 추적
- **Multi-Account** — Claude Code / Codex 멀티 계정 저장·전환·삭제·이름 변경
- **Menu Bar** — 아이콘 / 아이콘+토큰 수 / 아이콘+미니 그래프 모드
- **Color Themes** — 8가지 히트맵 컬러 테마 (Green, Blue, Purple, Orange, Red, Yellow, Pink, Rainbow)
- **Auto Update** — GitHub Releases에서 새 버전 자동 확인

## Install

[Releases](https://github.com/HongChaeMin/token-garden-app/releases)에서 DMG 다운로드 후 Applications에 드래그.

## Requirements

- macOS 14.0+

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme TokenGarden -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData \
  -configuration Release build
```

배포 방법은 [DEPLOY.md](DEPLOY.md) 참고.

## Architecture

```
TokenGarden/
├── AppDelegate.swift              # 앱 초기화, 메뉴바, 팝오버
├── MenuBar/
│   ├── MenuBarController.swift    # 상태바 표시 (아이콘/텍스트/그래프)
│   └── AnimationFrames.swift      # 식물 성장 애니메이션 (5프레임)
├── Services/
│   ├── TokenDataStore.swift       # SwiftData 저장소
│   ├── LogWatcher.swift           # FSEventStream 파일 감시 (Claude Code)
│   ├── CodexWatcher.swift         # SQLite 폴링 (Codex, 30s 주기)
│   ├── ProfileManager.swift       # Claude Code 멀티 계정 관리
│   ├── CredentialsManager.swift   # Keychain 자격증명 읽기/쓰기
│   └── UpdateChecker.swift        # GitHub release 업데이트 체크
├── Parsers/
│   └── ClaudeCodeLogParser.swift  # JSONL 로그 파싱
├── Models/
│   ├── DailyUsage.swift           # 일별 집계 (@Model)
│   ├── HourlyUsage.swift          # 시간별 집계 (@Model)
│   ├── SessionUsage.swift         # 세션 추적 (@Model)
│   ├── ProjectUsage.swift         # 프로젝트별 집계 (@Model)
│   ├── Profile.swift              # Claude Code 계정 프로필 (@Model)
│   ├── CodexProfile.swift         # Codex 계정 프로필 (@Model)
│   ├── TokenEvent.swift           # 파싱된 이벤트
│   └── HeatmapTheme.swift         # 컬러 테마
└── Views/
    ├── PopoverView.swift           # 메인 팝오버
    ├── HeatmapView.swift           # 캘린더 히트맵
    ├── StatsView.swift             # 통계 카드
    ├── ProjectListView.swift       # 프로젝트 목록
    ├── SessionListView.swift       # 활성 세션 목록
    ├── ProfileBannerView.swift     # 계정 배너 (Claude Code / Codex)
    ├── ProfileListView.swift       # Claude Code 계정 관리
    ├── CodexProfileListView.swift  # Codex 계정 관리
    ├── AccountsTabView.swift       # 계정 탭 (모델/계정별 차트)
    └── SettingsView.swift          # 설정
```

## License

MIT
