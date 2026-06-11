#!/bin/bash
# .env → app/PocketLlama/Generated/Secrets.swift 생성 (커밋 금지 대상)
# - .env 가 없거나 키가 비어 있어도 항상 스텁을 생성해 빌드가 깨지지 않게 한다.
#   (키가 빈 문자열이면 앱은 웹검색 tool 을 비활성화하고 설정 화면에 안내를 띄운다)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/app/PocketLlama/Generated"
OUT="$OUT_DIR/Secrets.swift"

TAVILY_API_KEY=""
if [ -f "$ROOT/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "$ROOT/.env"; set +a
fi

mkdir -p "$OUT_DIR"
cat > "$OUT" <<EOF
//
//  Secrets.swift  (자동 생성 — scripts/gen-secrets.sh, 커밋 금지)
//  원본은 레포 루트 .env. 키를 바꾸면 스크립트를 다시 실행할 것.
//

enum Secrets {
    /// Tavily 웹검색 API 키. 비어 있으면 앱이 웹검색 tool 을 비활성화한다.
    static let tavilyAPIKey = "${TAVILY_API_KEY}"
}
EOF

if [ -n "${TAVILY_API_KEY}" ]; then
  echo "OK: Secrets.swift 생성 (TAVILY_API_KEY 주입됨, 길이 ${#TAVILY_API_KEY})"
else
  echo "WARN: TAVILY_API_KEY 비어 있음 — 스텁 생성(웹검색 비활성)"
fi
