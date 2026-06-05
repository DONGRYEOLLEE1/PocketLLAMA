#!/usr/bin/env bash
# build-check.sh — SwiftUI(iOS) 프로젝트를 시뮬레이터 SDK로 컴파일/빌드해 에러를 빠르게 잡는다.
#
# 사용법:
#   build-check.sh [--project P.xcodeproj] [--scheme S] [--out FILE]
#     미지정 시 app/ → 현재 경로 순으로 *.xcodeproj 자동 탐색, scheme 도 자동 추출.
#
# 종료코드: 0 BUILD SUCCEEDED / 1 BUILD FAILED / 2 인자·환경오류
set -uo pipefail
die(){ echo "build-check: $*" >&2; exit 2; }

PROJECT=""; SCHEME=""; OUT=""
while [[ $# -gt 0 ]]; do case "$1" in
  --project) PROJECT=$2; shift 2;; --scheme) SCHEME=$2; shift 2;;
  --out) OUT=$2; shift 2;; *) die "알 수 없는 옵션: $1";; esac; done

command -v xcodebuild >/dev/null || die "xcodebuild 미설치(Xcode 필요)"

if [[ -z "$PROJECT" ]]; then
  PROJECT=$(find app . -maxdepth 3 -name '*.xcodeproj' -not -path '*/.*' 2>/dev/null | head -1)
fi
[[ -n "$PROJECT" && -e "$PROJECT" ]] || die "*.xcodeproj 를 찾지 못함 (--project 로 지정)"

if [[ -z "$SCHEME" ]]; then
  SCHEME=$(xcodebuild -project "$PROJECT" -list 2>/dev/null \
           | awk '/Schemes:/{f=1;next} f&&NF{gsub(/^[ \t]+/,"");print;exit}')
fi
[[ -n "$SCHEME" ]] || die "scheme 자동 추출 실패 (--scheme 로 지정)"

DD=/tmp/pocketllama-dd
COMMON=(-project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO)
PLATFORM="iOS Simulator"
echo "build-check: project=$PROJECT scheme=$SCHEME (iOS Simulator 시도)" >&2
log=$(xcodebuild "${COMMON[@]}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1) || true
# iOS 시뮬 런타임/플랫폼 미설치 환경이면 macOS SDK 컴파일로 폴백(크로스플랫폼 SwiftUI 타입 검증).
if ! printf '%s\n' "$log" | grep -q 'BUILD SUCCEEDED' \
   && printf '%s\n' "$log" | grep -qE 'Unable to find a destination|is not installed|Simulator device support disabled|CoreSimulator is out of date'; then
  echo "build-check: iOS 시뮬 미설치/불가 → macOS SDK 컴파일로 폴백" >&2
  PLATFORM="macOS (fallback — iOS 시뮬 미설치)"
  log=$(xcodebuild "${COMMON[@]}" -destination 'platform=macOS' CODE_SIGNING_REQUIRED=NO ENABLE_APP_SANDBOX=NO build 2>&1) || true
fi

errs=$(printf '%s\n' "$log"  | grep -cE ': error:' || true)
warns=$(printf '%s\n' "$log" | grep -cE 'warning:' || true)
ok=$(printf '%s\n' "$log"    | grep -c 'BUILD SUCCEEDED' || true)

{
  echo "# 빌드 검증 — $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- project: \`$PROJECT\`  scheme: \`$SCHEME\`  platform: $PLATFORM"
  echo "- 결과: $([[ "$ok" -gt 0 ]] && echo '✅ BUILD SUCCEEDED' || echo '❌ BUILD FAILED')"
  echo "- 에러: ${errs}  경고: ${warns}"
  if [[ "$errs" -gt 0 ]]; then
    echo; echo "## 컴파일 에러(상위 40줄)"; echo '```'
    printf '%s\n' "$log" | grep -E ': error:' | head -40
    echo '```'
  fi
} | { if [[ -n "$OUT" ]]; then tee "$OUT"; else cat; fi; }

[[ "$ok" -gt 0 ]]
