---
name: server-gate
description: 맥북 llama-server의 Anthropic /v1/messages 경로를 아이폰 접속 관점에서 검증하는 게이트 스모크. "서버 게이트", "Phase 0 게이트", "DoR 확인", "llama-server 스모크", "/v1/messages 테스트", "서버 0.0.0.0로 띄우고 검증", "/health·/v1/models 확인" 요청 시 반드시 이 스킬을 사용. 계획서 §2 Definition of Ready 8줄을 자동 검증한다. 후속: "게이트 다시", "인증 켜고 재검증", "스트리밍만 확인".
---

# Server Gate — Pre-Phase 0 게이트 스모크

iOS 코드를 짜기 전에, 맥북 `llama-server`가 **아이폰이 쓸 경로**(Anthropic `/v1/messages`)로 실제 동작하는지 먼저 실측한다. 계획서 §2가 "이 게이트 통과 = Definition of Ready, 통과 전 iOS 코드 금지"로 못박은 단계다 — 그래서 가장 먼저 자동화한다.

## 핵심: 스크립트로 검증한다
```bash
.claude/skills/server-gate/scripts/gate.sh [--host H] [--port P] [--serve] [--api-key KEY] [--out FILE]
```
- 기본: **떠 있는 서버**에 스모크. `--serve`: 안 떠 있으면 `0.0.0.0`으로 백그라운드 기동(모델 로딩 대기) 후 검증.
- LAN 타 기기 관점 검증은 `--host <맥북IP>`로(아이폰이 실제로 보는 주소).

## 검증 항목 (계획서 §2 8줄에 대응)
1. `LAN /health 200` — 서버 도달
2. `/v1/models 모델 표시` — `data[0].id` (계획서 §7.5 fallback 표시용)
3. `/v1/messages 비스트림 text 수신` — 앱이 쓸 경로가 실제 200 + 텍스트
4. `SSE text_delta 수신` — 스트리밍 경로 동작
5. (옵션 `--api-key`) **인증 헤더 형식 실측** — `x-api-key` vs `Authorization: Bearer` 중 어느 게 통하는지 → 계획서 §4.5에 고정

## 결과 해석
- 전체 PASS → ✅ DoR. iOS 구현(`ios-build`) 착수 가능.
- FAIL 있으면 → 서버 `0.0.0.0` 바인딩 여부·방화벽(8080)·동일 Wi-Fi·모델 로딩 완료를 점검 후 재실행.
- `/v1/models` 원본 JSON이 리포트에 포함 → 그대로 계획서 §7.5 샘플로 반영.
- `--out plans/_gate.md`로 저장하면 통과 기록을 남길 수 있다.

## 왜 이 단계가 먼저인가 (why)
앱이 쓸 경로(`/v1/messages`)는 기존 `test-client.sh`(OpenAI `/v1/chat/completions`)로는 검증되지 않는다. 경로·계약이 실측되지 않은 채 iOS를 많이 짜면 중반에 "404/파싱 실패/경로 없음"으로 되돌린다. 이 게이트가 그 위험을 착수 전에 제거한다.

## 주의
- `--serve`는 27GB 모델 로딩이라 첫 기동이 느리다(로그 `/tmp/llama-gate.log`). 기동한 서버는 남겨둔다(개발 중 재사용). 종료는 사용자가 `pkill -f llama-server`.
- 외부 공개 금지: `0.0.0.0`은 LAN 노출. 무인증이면 같은 Wi-Fi 누구나 접근(계획서 §4.5 보안 결정).
