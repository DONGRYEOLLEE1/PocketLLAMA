#!/usr/bin/env bash
# external-review.sh — agy(Gemini) / grok 외부 CLI로 "엄중(strict) 리뷰"를 받는다.
#
# 두 CLI는 cwd의 파일을 직접 읽는 agentic CLI다. 대상 경로만 주면 알아서 읽는다.
# 리뷰는 읽기 전용이 원칙이므로 프롬프트로 "수정/생성/삭제 금지"를 강제한다.
#
# 사용법:
#   external-review.sh <reviewer> <target> [옵션]
#     <reviewer>  agy | gemini | grok        (agy 와 gemini 는 동일 — Gemini CLI)
#     <target>    리뷰 대상 파일/디렉토리 경로 (프로젝트 루트 기준 또는 절대경로)
#
#   옵션:
#     --out <file>       리뷰 결과를 이 파일에 저장(헤더 포함). 미지정 시 stdout 만.
#     --model <id>       모델 오버라이드(미지정 시 각 CLI 기본 모델)
#     --rigor <level>    standard | strengthened(기본) | max
#     --focus "<text>"   집중 검토 영역(예: "API 계약·SSE 파싱·보안")
#     --context-dir <d>  참조용 추가 디렉토리(repeatable; 예: 외부 llm-serving)
#     --cwd <dir>        CLI 작업 디렉토리(기본: 현재 디렉토리)
#
# 예:
#   external-review.sh grok plans/mvp-plan.md --rigor strengthened \
#     --out plans/mvp-plan-review-grok.md --focus "API 계약·보안·ATS"
#   external-review.sh agy app/PocketLlama --rigor max --context-dir ../dev/llm-serving
#
# 종료코드: 0 성공 / 2 인자오류 / 3 CLI 미설치 / 그 외 = 해당 CLI 종료코드(미인증·타임아웃 등)
set -euo pipefail

die() { echo "external-review: $*" >&2; exit "${2:-2}"; }

[[ $# -ge 2 ]] || die "사용법: external-review.sh <agy|grok> <target> [옵션]"
REVIEWER="$1"; TARGET="$2"; shift 2

OUT=""; MODEL=""; RIGOR="strengthened"; FOCUS=""; CWD="$(pwd)"
CONTEXT_DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)         OUT="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --rigor)       RIGOR="$2"; shift 2 ;;
    --focus)       FOCUS="$2"; shift 2 ;;
    --context-dir) CONTEXT_DIRS+=("$2"); shift 2 ;;
    --cwd)         CWD="$2"; shift 2 ;;
    *) die "알 수 없는 옵션: $1" ;;
  esac
done

case "$RIGOR" in standard|strengthened|max) ;; *) die "잘못된 --rigor: $RIGOR (standard|strengthened|max)" ;; esac
[[ -e "$TARGET" ]] || die "대상이 존재하지 않음: $TARGET"

# --- 엄중 리뷰 프롬프트 구성 (한국어, 결과물도 한국어로 받음) ---
read -r -d '' PROMPT <<EOF || true
당신은 타협 없는 깐깐한 시니어 리뷰어이자 감사관이다. 아첨하지 말고, 칭찬은 최소화하고,
결함과 위험을 끝까지 파고든다. 추측이 아니라 파일을 직접 열어 근거를 들고 비판하라.

[대상] ${TARGET}
${FOCUS:+[집중 검토] ${FOCUS}}
${CONTEXT_DIRS:+[참조 가능 디렉토리] ${CONTEXT_DIRS[*]}}

[리뷰 원칙]
- 읽기 전용: 어떤 파일도 수정/생성/삭제하지 마라. 명령 실행은 사실 확인(읽기·grep·빌드 설정 조회)에 한정.
- 환각 금지: 단정 전에 해당 파일·줄을 실제로 확인하라. 확인 못 한 추정은 "미검증"으로 표시.
- 근거 제시: 모든 지적에 파일 경로와 섹션/줄 위치를 붙여라.
- 심각도 분류: 각 지적을 [Blocker] / [Major] / [Minor] 로 표시.
  - Blocker: 이대로 가면 빌드 실패·런타임 오류·잘못된 전제로 되돌림이 발생.
  - Major: 구현 중 반드시 보완해야 함.
  - Minor: 정합성·가독성·사소한 개선.
- 실행 가능성: 각 지적에 "무엇을 어떻게 고칠지" 구체적 대안을 1줄 이상.
- 과장 금지: 위험을 부풀리지 말고, 반대로 실제 위험을 축소하지도 마라. 근거 없는 위험은 "과장 가능성"으로 명시.

[출력 형식] 마크다운으로:
1. 총평 (3~5줄, 핵심 위험 우선)
2. Blocker (있으면)
3. Major
4. Minor / 정합성
5. 검증한 사실 (실제로 열어본 파일·확인 항목)
EOF

# rigor 에 따른 자기검증 강화 지시(agy 처럼 effort/check 플래그가 없는 CLI 대비, 프롬프트로도 강제)
case "$RIGOR" in
  strengthened) PROMPT+=$'\n\n[자기검증] 초안을 낸 뒤, 스스로 "이 지적이 정말 사실인가? 과장은 없는가? 놓친 Blocker는 없는가?"를 한 번 더 반박·재검토하고 최종본만 출력하라.' ;;
  max)          PROMPT+=$'\n\n[자기검증·최고강도] 서로 다른 관점(정확성/보안/유지보수성)으로 여러 번 검토하고, 가장 치명적인 결함부터 우선순위화하라. 확신이 낮은 지적은 근거와 함께 "불확실"로 표기하라.' ;;
esac

# --- CLI 호출 ---
run_agy() {
  command -v agy >/dev/null 2>&1 || die "agy 미설치(또는 PATH에 없음)" 3
  local cmd=(agy -p "$PROMPT" --print-timeout 15m --dangerously-skip-permissions --add-dir "$CWD")
  [[ -n "$MODEL" ]] && cmd+=(--model "$MODEL")
  local d; for d in "${CONTEXT_DIRS[@]:-}"; do [[ -n "$d" ]] && cmd+=(--add-dir "$d"); done
  ( cd "$CWD" && "${cmd[@]}" )
}

run_grok() {
  command -v grok >/dev/null 2>&1 || die "grok 미설치(또는 PATH에 없음)" 3
  local cmd=(grok -p "$PROMPT" --cwd "$CWD" --output-format plain --permission-mode dontAsk)
  [[ -n "$MODEL" ]] && cmd+=(-m "$MODEL")
  case "$RIGOR" in
    standard)     cmd+=(--effort medium) ;;
    strengthened) cmd+=(--effort high --check) ;;
    max)          cmd+=(--effort xhigh --best-of-n 3) ;;
  esac
  "${cmd[@]}"
}

case "$REVIEWER" in
  agy|gemini) LABEL="Gemini (agy)"; OUTPUT="$(run_agy)" ;;
  grok)       LABEL="Grok (grok)";  OUTPUT="$(run_grok)" ;;
  *) die "알 수 없는 reviewer: $REVIEWER (agy|gemini|grok)" ;;
esac

# --- 출력 ---
if [[ -n "$OUT" ]]; then
  {
    echo "# 외부 엄중 리뷰 — ${LABEL}"
    echo
    echo "- 대상: \`${TARGET}\`"
    echo "- 엄중도(rigor): ${RIGOR}"
    [[ -n "$MODEL" ]] && echo "- 모델: ${MODEL}"
    [[ -n "$FOCUS" ]] && echo "- 집중 검토: ${FOCUS}"
    echo "- 생성: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    echo "---"
    echo
    echo "$OUTPUT"
  } > "$OUT"
  echo "external-review: 저장됨 → $OUT" >&2
fi
echo "$OUTPUT"
