#!/usr/bin/env bash
# PocketLlama 서버 — llama-server 를 OpenAI + Anthropic 호환 API 로 띄운다.
# 원본 SSOT: ~/workspace/dev/llm-serving/scripts/serve.sh 의 아이폰 접속용 변형(HOST 지원).
#
# 사용법:
#   ./server/serve.sh                       # 로컬 기본 모델(없으면 -hf 자동 다운로드)
#   HOST=0.0.0.0 ./server/serve.sh          # 아이폰/LAN 접속 (계획서 §6)
#   ./server/serve.sh models/내모델.gguf     # 로컬 GGUF
#   ./server/serve.sh repo/name:QUANT        # HuggingFace repo:quant
#
# 환경변수: HOST(기본 127.0.0.1) · PORT(8080) · CTX(65536) · KVQ(q8_0; f16이면 끔)
#           THINK(off/on/auto) · API_KEY(설정 시 인증 켬 — 헤더 형식은 계획서 §4.5 실측)
#           MODEL(첫 인자 대용 — 로컬 경로/HF; 인자 미지정 시 폴백)
# 이식성: 다른 머신은 첫 인자/MODEL(로컬 경로/HF) 또는 LLAMA_CACHE 로 모델 위치를 바꾼다.
#   예) MODEL=/path/to/model.gguf ./server/serve.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LLAMA_CACHE="${LLAMA_CACHE:-$ROOT/models}"   # -hf 캐시를 프로젝트 models/ 로

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX="${CTX:-65536}"
KVQ="${KVQ:-q8_0}"
THINK="${THINK:-off}"
APIKEY="${API_KEY:-}"

LOCAL_DEFAULT="$ROOT/models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"
DEFAULT_HF="unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q5_K_XL"

ARG="${1:-${MODEL:-}}"
if [[ -n "$ARG" && -f "$ARG" ]]; then SRC=(-m "$ARG");           echo ">> 로컬 모델: $ARG"
elif [[ -n "$ARG" ]];            then SRC=(-hf "$ARG");          echo ">> HF 모델: $ARG"
elif [[ -f "$LOCAL_DEFAULT" ]];  then SRC=(-m "$LOCAL_DEFAULT"); echo ">> 기본(로컬): $(basename "$LOCAL_DEFAULT")"
else                                  SRC=(-hf "$DEFAULT_HF");   echo ">> 기본: $DEFAULT_HF (다운로드)"
fi

KV_FLAGS=()
[[ "$KVQ" != "f16" ]] && KV_FLAGS=(--cache-type-k "$KVQ" --cache-type-v "$KVQ")

echo ">> http://$HOST:$PORT  (OpenAI /v1 · Anthropic /v1/messages · 웹UI /)  ctx=$CTX kv=$KVQ think=$THINK"
if [[ "$HOST" == "0.0.0.0" && -z "$APIKEY" ]]; then
  echo ">> ⚠️ 0.0.0.0 + 무인증: 같은 Wi-Fi 의 누구나 접근 가능. 신뢰된 가정용 LAN 에서만 쓰고, 외부망 노출 금지(Tailscale 은 계획서 Phase 10)."
fi

exec llama-server \
  "${SRC[@]}" \
  --host "$HOST" \
  --port "$PORT" \
  -c "$CTX" \
  -ngl 999 \
  -fa on \
  "${KV_FLAGS[@]}" \
  --reasoning "$THINK" \
  --jinja \
  --temp 1.0 --top-p 0.95 --top-k 20 \
  ${APIKEY:+--api-key "$APIKEY"}
