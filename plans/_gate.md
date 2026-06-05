# 서버 게이트 스모크 — 2026-06-05 22:44:03 +0900
- 대상: http://127.0.0.1:8080   모델: Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf

- PASS | LAN /health 200 — HTTP 200
- PASS | /v1/models 모델 표시 — id=Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf
- PASS | /v1/messages 비스트림 text 수신 — Pong
- PASS | SSE text_delta 수신

결과: ✅ 게이트 통과 — Definition of Ready

## /v1/models 원본(샘플로 계획서 §7.5에 반영)
```json
{"models":[{"name":"Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf","model":"Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf","modified_at":"","size":"","digest":"","type":"model","description":"","tags":[""],"capabilities":["completion"],"parameters":"","details":{"parent_model":"","format":"gguf","family":"","families":[""],"parameter_size":"","quantization_level":""}}],"object":"list","data":[{"id":"Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf","aliases":[],"tags":[],"object":"model","created":1780667041,"owned_by":"llamacpp","meta":{"vocab_type":2,"n_vocab":248320,"n_ctx":65536,"n_ctx_train":262144,"n_embd":2048,"n_params":35505251456,"size":27148124672}}]}
```
