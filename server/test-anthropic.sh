#!/usr/bin/env bash
# 앱이 쓸 경로(Anthropic /v1/messages)를 비스트림+스트림 1회씩 스모크.
# 더 완전한 게이트(계획서 §2 8줄)는: .claude/skills/server-gate/scripts/gate.sh
#
# 사용법: [HOST=<IP>] [PORT=8080] ./server/test-anthropic.sh ["프롬프트"]
set -euo pipefail
HOST="${HOST:-127.0.0.1}"; PORT="${PORT:-8080}"; P="${1:-ping. 한 단어로만 답해.}"
BASE="http://$HOST:$PORT"

echo "== 비스트림 (model: local, max_tokens 필수) =="
curl -s "$BASE/v1/messages" \
  -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d "{\"model\":\"local\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"$P\"}]}" \
  | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("text:", "".join(b.get("text","") for b in d.get("content",[]) if b.get("type")=="text"))
print("stop_reason:", d.get("stop_reason"))'

echo "== 스트림 (text_delta 일부) =="
curl -sN "$BASE/v1/messages" \
  -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d "{\"model\":\"local\",\"max_tokens\":64,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"$P\"}]}" \
  | grep '"text_delta"' | head -3
