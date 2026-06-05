# server/ — llama.cpp 서빙 (PocketLlama 백엔드)

맥북에서 `llama-server`를 띄워 아이폰 앱(PocketLlama)이 붙을 **Anthropic 호환 `/v1/messages`** API를 제공한다.

> 원본 SSOT는 `~/workspace/dev/llm-serving/scripts/`. 여기 `serve.sh`는 그 **아이폰 접속용 변형**(`HOST` 지원)이다.

## 기동

```bash
# 로컬 전용
./server/serve.sh

# 아이폰/LAN 접속 (계획서 §6) — 0.0.0.0 바인딩
HOST=0.0.0.0 ./server/serve.sh
```

- 포트 `8080`. 엔드포인트: OpenAI `/v1/chat/completions` · Anthropic `/v1/messages` · `/health` · `/v1/models` · 웹 UI `/`
- 모델 기본값: 프로젝트 `models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf` (gitignore 대상, 하드링크)
- thinking 기본 `THINK=off`(응답성). 추론은 `THINK=on`.

## 검증

```bash
# 앱 경로 빠른 스모크
HOST=0.0.0.0 ./server/test-anthropic.sh "안녕"

# 계획서 §2 게이트 8줄(권장)
.claude/skills/server-gate/scripts/gate.sh --serve --out plans/_gate.md
```

## ⚠️ 보안 (계획서 §4.5)
`0.0.0.0`은 같은 Wi-Fi 전체에 노출된다. 기본은 **무인증** — 신뢰된 가정용 LAN에서만 쓰고 외부망에 직접 노출하지 말 것(원격은 Tailscale, 계획서 Phase 10).
인증을 켜려면 `API_KEY=<키> HOST=0.0.0.0 ./server/serve.sh` — 단 Anthropic 경로의 인증 헤더 형식(`x-api-key` vs `Authorization: Bearer`)은 `gate.sh --api-key <키>`로 실측해 계획서 §4.5에 고정한다.

## 이식성 (다른 머신)
모델 경로가 이 맥에 고정돼 있다. 다른 머신에서는:
- 첫 인자로 경로/HF 지정: `./server/serve.sh /path/to/model.gguf` 또는 `./server/serve.sh repo/name:QUANT`
- 또는 `LLAMA_CACHE=<dir>`로 `-hf` 캐시 위치 변경

## 종료
```bash
pkill -f llama-server
```
