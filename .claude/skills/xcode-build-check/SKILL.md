---
name: xcode-build-check
description: SwiftUI(iOS) 프로젝트를 시뮬레이터 SDK로 컴파일/빌드해 컴파일 에러를 빠르게 잡는 검증 도구. "빌드 확인", "컴파일 되는지 봐", "xcodebuild", "SwiftUI 빌드 검증", "에러 없는지 빌드" 요청 시, 또는 ios-build 하네스의 QA 단계에서 사용. 코드 작성 후 실기기 설치 전에 컴파일 가능 여부를 확인할 때 반드시 사용. 후속: "다시 빌드", "특정 스킴으로 빌드".
---

# Xcode Build Check — 컴파일/빌드 검증

작성한 Swift 코드가 실제로 **컴파일되는지** 시뮬레이터 SDK로 빠르게 확인한다. 실기기 설치(Xcode GUI)는 사람이 하지만, 그 전에 컴파일 에러를 잡아 왕복을 줄인다 — iOS 초보자가 "UI 문제"와 "컴파일 문제"를 동시에 디버깅하지 않게 하는 게 목적이다.

## 핵심: 스크립트로 검증한다
```bash
.claude/skills/xcode-build-check/scripts/build-check.sh [--project P.xcodeproj] [--scheme S] [--out FILE]
```
- 미지정 시 `app/` → 현재 경로에서 `*.xcodeproj`를 자동 탐색하고 scheme도 자동 추출.
- 시뮬레이터 SDK(`iphonesimulator`, `generic/platform=iOS Simulator`)로 빌드 — 코드 서명·실기기 불필요.

## 결과 해석
- `✅ BUILD SUCCEEDED` + 에러 0 → 컴파일 통과. 다음 단계(실기기 실행/QA 계속).
- `❌ BUILD FAILED` → 리포트의 "컴파일 에러" 섹션(상위 40줄)을 보고 수정. 종료코드 1.
- 경고 수는 참고용(차단 아님).

## 언제 호출하나
- `swift-builder`가 한 모듈/Phase를 작성한 직후(incremental).
- `ios-qa`의 검증 단계 — 경계면 비교(런타임)와 별개로 **정적 컴파일**을 먼저 통과시킨다.

## 주의
- `.xcodeproj`가 없으면(빈 템플릿 단계) 실패한다 — 계획서 Phase 1(신규 `PocketLlama` 생성)은 Xcode GUI로 사람이 먼저 만들어야 한다.
- `derivedDataPath`는 `/tmp/pocketllama-dd`로 격리(레포 오염 방지).
- 빌드는 느릴 수 있다(첫 빌드 수십 초~분). 컴파일 에러만 빨리 보려면 출력의 error 라인에 집중.
