#!/usr/bin/env bash
# gate.sh — llama-server Anthropic /v1/messages "Pre-Phase 0 게이트" 스모크.
# 계획서 §2 Definition of Ready 8줄을 자동 검증한다.
#
# 사용법:
#   gate.sh [--host H] [--port P] [--serve] [--model-path PATH] [--api-key KEY] [--out FILE]
#     --serve        서버가 안 떠 있으면 llama-server 를 0.0.0.0 으로 백그라운드 기동 후 검증
#     --api-key KEY  인증 켠 서버 검증 + Anthropic 경로 헤더 형식(x-api-key vs Bearer) 실측
#     --out FILE     리포트를 파일에도 저장
#
# 각 체크는 독립 판정(한 체크 실패해도 나머지 진행). 종료코드: 0 전체통과 / 1 일부FAIL / 2 인자·환경오류
set -uo pipefail
die(){ echo "gate: $*" >&2; exit 2; }

HOST=127.0.0.1; PORT=8080; SERVE=0; API_KEY=""; OUT=""
MODEL_PATH="${HOME}/workspace/dev/llm-serving/models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
while [[ $# -gt 0 ]]; do case "$1" in
  --host) HOST=$2; shift 2;; --port) PORT=$2; shift 2;;
  --serve) SERVE=1; shift;; --model-path) MODEL_PATH=$2; shift 2;;
  --api-key) API_KEY=$2; shift 2;; --out) OUT=$2; shift 2;;
  *) die "알 수 없는 옵션: $1";; esac; done

BASE="http://${HOST}:${PORT}"
command -v curl    >/dev/null || die "curl 필요"
command -v python3 >/dev/null || die "python3 필요"

if [[ $SERVE == 1 ]]; then
  if curl -sf "$BASE/health" >/dev/null 2>&1; then
    echo "gate: 서버 이미 떠있음 ($BASE)" >&2
  else
    command -v llama-server >/dev/null || die "llama-server 미설치"
    [[ -f "$MODEL_PATH" ]] || die "모델 없음: $MODEL_PATH (--model-path 지정)"
    echo "gate: llama-server 0.0.0.0:$PORT 기동 — 모델 로딩 대기(로그 /tmp/llama-gate.log)…" >&2
    nohup llama-server -m "$MODEL_PATH" --host 0.0.0.0 --port "$PORT" \
      -ngl 999 -fa on --jinja --reasoning off --cache-type-k q8_0 --cache-type-v q8_0 -c 65536 \
      ${API_KEY:+--api-key "$API_KEY"} >/tmp/llama-gate.log 2>&1 &
    disown 2>/dev/null || true
    for _ in $(seq 1 180); do curl -sf "$BASE/health" >/dev/null 2>&1 && break; sleep 2; done
  fi
fi

hdr=(-H "Content-Type: application/json" -H "anthropic-version: 2023-06-01")
auth=(); [[ -n $API_KEY ]] && auth=(-H "x-api-key: $API_KEY")
RESULTS=()
add(){ RESULTS+=("$1"); }
check(){ local m; [[ $2 -eq 0 ]] && m="PASS" || m="FAIL"; add "$m | $1${3:+ — $3}"; }

# 1) /health
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$BASE/health" 2>/dev/null)
[[ "$code" == 200 ]]; check "LAN /health 200" $? "HTTP ${code:-000}"

# 2) /v1/models 표시
models_json=$(curl -s --max-time 8 "$BASE/v1/models" 2>/dev/null)
mid=$(printf '%s' "$models_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null)
[[ -n "$mid" ]]; check "/v1/models 모델 표시" $? "id=${mid:-?}"

# 3) /v1/messages 비스트림 200 + text
body='{"model":"local","max_tokens":32,"messages":[{"role":"user","content":"ping. 한 단어로만 답해."}]}'
ns=$(curl -s --max-time 180 "$BASE/v1/messages" "${hdr[@]}" ${auth[@]+"${auth[@]}"} -d "$body" 2>/dev/null)
text=$(printf '%s' "$ns" | python3 -c 'import sys,json
d=json.load(sys.stdin); print("".join(b.get("text","") for b in d.get("content",[]) if b.get("type")=="text"))' 2>/dev/null)
[[ -n "$text" ]]; check "/v1/messages 비스트림 text 수신" $? "${text:0:48}"

# 4) 스트림 SSE text_delta
sbody='{"model":"local","max_tokens":32,"stream":true,"messages":[{"role":"user","content":"ping"}]}'
sse=$(curl -sN --max-time 180 "$BASE/v1/messages" "${hdr[@]}" ${auth[@]+"${auth[@]}"} -d "$sbody" 2>/dev/null)
printf '%s' "$sse" | grep -q '"type":"text_delta"'; check "SSE text_delta 수신" $?

# 5) (옵션) 인증 헤더 형식 실측 — 계획서 §4.5
if [[ -n "$API_KEY" ]]; then
  cx=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$BASE/v1/messages" "${hdr[@]}" -H "x-api-key: $API_KEY" -d "$body" 2>/dev/null)
  cb=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$BASE/v1/messages" "${hdr[@]}" -H "Authorization: Bearer $API_KEY" -d "$body" 2>/dev/null)
  add "INFO | 인증 헤더 실측 — x-api-key:HTTP ${cx}, Authorization\\:Bearer:HTTP ${cb} (200 쪽을 §4.5에 고정)"
fi

FAIL=0; printf '%s\n' "${RESULTS[@]}" | grep -q '^FAIL' && FAIL=1
{
  echo "# 서버 게이트 스모크 — $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- 대상: ${BASE}   모델: $(basename "$MODEL_PATH")"
  echo
  for r in "${RESULTS[@]}"; do echo "- $r"; done
  echo
  [[ $FAIL -eq 0 ]] && echo "결과: ✅ 게이트 통과 — Definition of Ready" \
                    || echo "결과: ❌ 미통과 — FAIL 항목 해결 후 재실행 (서버 0.0.0.0 바인딩·방화벽·모델 로딩 확인)"
  echo
  echo "## /v1/models 원본(샘플로 계획서 §7.5에 반영)"; echo '```json'; printf '%s\n' "${models_json:-(없음)}"; echo '```'
} | { if [[ -n "$OUT" ]]; then tee "$OUT"; else cat; fi; }

exit $FAIL
