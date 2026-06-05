# MacBook Ollama -> iPhone App 조사

작성일: 2026-04-02

> **⚠️ v2 백엔드 전환(2026-06-05):** 이 문서는 초기 `Ollama` 전제로 작성됐다. 실제 구현은 **`llama.cpp`(`llama-server`) + Anthropic 호환 `/v1/messages`**(모델 `Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf`, 포트 8080)로 전환됐다. 현행 전제·계약은 계획서 `plans/swiftui-ollama-ios-mvp-plan.md`(v3)를 따른다. 아래 조사 내용은 의사결정 기록으로 보존한다.

## 목표

맥북에서 `Ollama`로 LLM 서버를 띄우고, 아이폰에서 앱 형태로 접속해 실제로 써보는 경로를 조사했다.  
핵심 질문은 다음이다.

1. `Ollama`를 이미 띄운 뒤 다음 단계는 무엇인가?
2. 비슷한 사례들은 어떤 방식으로 연결했는가?
3. 내 경우 어떤 아키텍처가 가장 현실적인가?

## 현재 환경 확인

로컬에서 직접 확인한 결과:

- `ollama --version` -> `0.19.0`
- `curl http://127.0.0.1:11434/api/tags` 응답 정상
- 현재 등록 모델은 `qwen3-coder-next:cloud`, `minimax-m2.7:cloud`

중요한 점:

- 지금은 `Ollama` 서버 자체는 잘 떠 있지만, 현재 목록은 `:cloud` 모델뿐이다.
- 즉 "맥북에서 완전 로컬 추론"을 목표로 한다면, 다음 단계는 앱을 만들기 전에 로컬 모델을 하나 이상 내려받는 것이다.
- `Ollama` 공식 FAQ는 클라우드 기능을 끄는 방법도 제공한다. 완전 로컬 모드가 목적이면 `disable_ollama_cloud` 또는 `OLLAMA_NO_CLOUD=1`을 고려할 수 있다.

## 한 줄 결론

지금 필요한 다음 단계는 `앱 개발`보다 먼저:

1. 로컬 모델 하나를 실제로 pull
2. 아이폰이 접근할 네트워크 경로를 정함
3. 가장 빠른 검증은 `Open WebUI + iPhone Safari/PWA`
4. 그 다음이 `SwiftUI 네이티브 앱`

## 조사된 유사 사례

### 1. Enchanted

- App Store 설명에 따르면 `running Ollama server`가 필요하고, 앱 설정에서 서버 endpoint를 지정해 사용한다.
- 스트리밍과 최신 Chat API 컨텍스트를 지원한다.
- 시사점: 아이폰 앱에서 `맥북의 Ollama endpoint`를 직접 받아 붙는 패턴은 이미 성립된 방식이다.

링크:

- https://apps.apple.com/us/app/enchanted-developers-only/id6474268307

### 2. MyOllama

- GitHub README에서 "Ollama가 설치된 컴퓨터에 연결하는 모바일 클라이언트"라고 설명한다.
- 핵심 기능으로 `IP address` 기반 원격 연결을 제시한다.
- 사용법에도 `Ollama remotely accessible` 설정 후 앱에 컴퓨터 IP를 입력하라고 적혀 있다.

링크:

- https://github.com/bipark/my_ollama_app

### 3. LLM Bridge

- iOS/macOS 멀티플랫폼 클라이언트이며 Ollama, LM Studio, Claude, OpenAI를 함께 지원한다.
- README에 `Remote LLM Access: Connect to Ollama/LM Studio host via IP address`가 명시되어 있다.
- iOS 요구사항도 "same network"를 전제로 적고 있어, 로컬 Wi-Fi 또는 사설망 접근이 기본 시나리오임을 보여준다.

링크:

- https://github.com/bipark/swift_llm_bridge
- https://apps.apple.com/us/app/llm-bridge-multi-llm-client/id6738298481

### 4. Mocolamma

- macOS/iOS/iPadOS에서 네트워크상의 Ollama 서버에 연결해 모델을 관리하고 간단한 채팅 테스트를 하는 앱이다.
- 여러 Ollama 서버를 추가하고 전환하는 흐름을 제공한다.
- 시사점: 아이폰 앱은 단순 채팅뿐 아니라 서버 관리 UI로도 충분히 확장 가능하다.

링크:

- https://mocolamma.taikun.design/

### 5. Valdis

- 공식 사이트 설명상, iPhone 앱이 `Mac-hosted Ollama or LM Studio`와 연결된다.
- 연결 경로로 `Tailscale`, `VPN`, `local network`를 직접 언급한다.
- 시사점: 로컬 네트워크만이 아니라, 사설망 기반 원격 접근도 실사용 패턴이다.

링크:

- https://www.valdis.app/

### 6. Open WebUI

- GitHub README에서 `Ollama/OpenAI API Integration`, `Responsive Design`, `Progressive Web App (PWA) for Mobile`를 명시한다.
- 즉 네이티브 앱을 바로 만들지 않아도, 맥북에서 Open WebUI를 띄우고 아이폰 Safari 홈 화면에 추가해 앱처럼 먼저 검증할 수 있다.

링크:

- https://github.com/open-webui/open-webui
- https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-ollama/

## 권장 아키텍처 비교

### A. 가장 빠른 검증: Open WebUI + iPhone Safari/PWA

구성:

- MacBook: `Ollama` + `Open WebUI`
- iPhone: Safari 접속 후 홈 화면 추가

장점:

- 가장 빨리 결과를 볼 수 있다.
- 채팅 UI, 파일 업로드, 모델 전환, 대화 기록을 바로 쓸 수 있다.
- 네이티브 앱 제작 전에 네트워크/모델/UX를 검증할 수 있다.

단점:

- 진짜 네이티브 iOS 앱은 아니다.
- 카메라, 음성, 백그라운드 처리 같은 iOS 네이티브 경험은 제한적일 수 있다.

추천도:

- 첫 실험용으로 가장 추천

### B. 본선 MVP: SwiftUI 네이티브 앱 -> Ollama API

구성:

- iPhone 앱: SwiftUI + `URLSession`
- 서버: MacBook `Ollama`
- API: `POST /api/chat` 또는 OpenAI 호환 `/v1/chat/completions`, `/v1/responses`

장점:

- 진짜 앱 형태로 배포 가능
- iOS UX를 마음대로 설계 가능
- 음성 입력, 카메라, 사진, 오프라인 캐시 등 확장성이 높다

단점:

- Info.plist, 로컬 네트워크 권한, 연결 재시도, 스트리밍 처리 등을 직접 구현해야 한다

추천도:

- PWA 검증 후 바로 이어갈 두 번째 단계로 추천

### C. 외부망 공개: Reverse Proxy / ngrok / Cloudflare Tunnel / Funnel

구성:

- MacBook `Ollama`
- 프록시 또는 터널
- iPhone 앱이 외부 인터넷에서 접속

장점:

- 집 밖에서도 접속 가능

단점:

- 보안 부담이 커진다
- 인증, HTTPS, 접근제어 없이는 위험하다
- 초반 실험 단계에서 과한 선택일 수 있다

추천도:

- 첫 단계로는 비추천

## 내 경우의 추천 경로

가장 현실적인 순서는 아래다.

### 1단계: 진짜 로컬 모델 확보

현재는 `:cloud` 모델만 있으므로 로컬 모델 하나는 반드시 받아 두는 게 좋다.

예시:

```bash
ollama pull llama3.2:3b
```

또는 조금 더 최신 계열을 보고 싶다면:

```bash
ollama pull qwen3:4b
```

참고:

- `llama3.2:3b`는 Ollama 라이브러리에서 기본 3B 텍스트 모델로 안내된다.
- `qwen3` 계열은 0.6B, 1.7B, 4B, 8B 등 여러 크기를 제공한다.

### 2단계: 아이폰에서 접근 가능한 경로 선택

선택지는 사실상 3개다.

#### 같은 Wi-Fi에서 직접 접근

- MacBook의 로컬 IP 예: `http://192.168.0.10:11434`
- 가장 단순하다.
- 단, `Ollama` 기본 바인드는 `127.0.0.1`라서 외부 기기에서 안 보인다.
- 공식 FAQ 기준으로 `OLLAMA_HOST`를 바꿔야 한다.

macOS 앱 기준 예시:

```bash
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
```

그리고 Ollama 앱 재시작.

#### Tailscale 사설망으로 접근

- MacBook과 iPhone에 Tailscale 설치
- 같은 tailnet에 넣고 사설 주소 또는 Serve URL로 접근
- 집 밖에서도 비교적 안전하게 접속 가능

이 경로를 추천하는 이유:

- 공개 인터넷에 포트를 직접 열지 않아도 된다
- Tailscale Serve는 tailnet 내부에만 서비스 공유가 가능하다
- HTTPS 인증서도 자동 프로비저닝 가능하다

예시 개념:

```bash
tailscale serve 11434
```

또는 최신 문법으로 HTTPS 포트 지정:

```bash
tailscale serve --https=443 11434
```

이 경우 아이폰 앱은 `https://<device>.<tailnet>.ts.net` 같은 URL로 붙을 수 있다.

#### 공개 인터넷 노출

Ollama FAQ가 예시로 제공하는 방식:

```bash
ngrok http 11434 --host-header="localhost:11434"
```

```bash
cloudflared tunnel --url http://localhost:11434 --http-host-header="localhost:11434"
```

하지만 이 방식은 인증/접근제어를 먼저 설계하지 않으면 권장하기 어렵다.

### 3단계: iPhone 앱 형태 결정

#### 빠른 검증용

- `Open WebUI`
- 아이폰 Safari
- 홈 화면 추가

#### 네이티브 MVP

- SwiftUI
- 스트리밍 응답 표시
- 서버 URL/모델 선택 화면
- 대화 기록 로컬 저장

## iOS 쪽 구현 포인트

### 1. 로컬 네트워크 권한

Apple은 iOS 14 이후 로컬 네트워크 접근에 대해 사용자 허용 흐름을 요구한다.

필수 또는 사실상 필수에 가까운 항목:

- `NSLocalNetworkUsageDescription`

Bonjour 탐색까지 쓰면 추가:

- `NSBonjourServices`

중요:

- 앱 시작 직후 무작정 네트워크 브로드캐스트를 날리기보다, 실제 사용자가 "서버 찾기" 또는 "연결"을 눌렀을 때 권한 흐름이 발생하도록 만드는 편이 좋다.

### 2. ATS(App Transport Security)

Apple 문서상 ATS는 공인 호스트명에 대한 연결에 적용되고, IP 주소나 `.local`/unqualified host는 별도 취급된다.

핵심 포인트:

- IP 주소 연결은 ATS 보호 대상이 아니다.
- `.local` 또는 미완성 호스트명을 쓰려면 `NSAllowsLocalNetworking=YES`가 필요하다.
- Apple은 로컬 연결이라도 TLS 사용을 강하게 권장한다.

실무 해석:

- 빠른 LAN 실험은 `http://192.168.x.x:11434`로 시작 가능
- 장기적으로는 `Tailscale Serve` 같은 HTTPS 경로가 더 깔끔하다

### 3. 연결 재시도

Apple WWDC 자료는 로컬 네트워크/변동 네트워크 환경에서 `waitsForConnectivity` 사용을 권장한다.

즉:

- 앱이 미리 네트워크 가능 여부를 추측하지 말고
- 실제 요청을 보내고
- 연결 가능해질 때까지 시스템에게 기다리게 하는 쪽이 낫다

### 4. 어떤 Swift 클라이언트를 쓸 것인가

선택지는 두 갈래다.

#### 선택지 A: Ollama 전용 Swift 클라이언트

예:

- `OllamaKit`
- `ollama-swift`

장점:

- Ollama 고유 API에 직접 맞춰져 있다

단점:

- 다른 공급자와의 호환성은 상대적으로 좁다

#### 선택지 B: OpenAI 호환 클라이언트

Ollama 공식 문서는 `/v1/chat/completions`, `/v1/responses` 호환을 제공한다고 밝힌다.

즉:

- OpenAI 호환 Swift SDK를 쓰고
- `baseURL`만 `http://<ollama-host>:11434/v1/`로 바꿔도 된다

장점:

- 나중에 OpenAI, Groq, OpenRouter, LM Studio로 바꾸기 쉽다

내 추천:

- 장기적으로는 OpenAI 호환 경로가 더 유연하다
- 하지만 첫 MVP는 `URLSession + /api/chat`로 직접 붙는 것이 디버깅이 가장 쉽다

## 바로 실행할 다음 순서

### 가장 추천하는 현실적인 순서

1. 로컬 모델 pull
2. `Open WebUI`를 붙여서 아이폰 Safari/PWA로 먼저 검증
3. 원하는 UX가 보이면 SwiftUI 앱 착수
4. 접근 경로는 `같은 Wi-Fi`에서 시작하고, 원격 접속은 `Tailscale`로 확장

### 최소 실행 체크리스트

```bash
ollama pull llama3.2:3b
curl http://127.0.0.1:11434/api/tags
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
```

그 다음:

- MacBook에서 Ollama 재시작
- 아이폰과 맥북을 같은 네트워크에 연결
- 아이폰 브라우저 또는 앱에서 `http://<맥북IP>:11434/api/tags` 수준부터 확인

### 완전 로컬 지향이면

```json
{
  "disable_ollama_cloud": true
}
```

파일 위치:

- `~/.ollama/server.json`

또는:

```bash
export OLLAMA_NO_CLOUD=1
```

## 추천 구현 방향

내 추천은 아래다.

### 추천안 1: 가장 빠른 성공 경로

- 프로젝트 초기 목표: "아이폰에서 내 맥북 LLM에게 묻고 답받기"
- 구현: `Ollama + Open WebUI + iPhone PWA`

이 조합이 좋은 이유:

- 앱처럼 바로 써볼 수 있다
- 네트워크/모델/지연시간/발열/절전 문제를 먼저 검증할 수 있다
- 실패 지점이 적다

### 추천안 2: 바로 앱까지 가고 싶다면

- 서버: `Ollama`
- 네트워크: `same Wi-Fi` 또는 `Tailscale`
- 클라이언트: `SwiftUI`
- API: 우선 `/api/chat`, 이후 필요시 `/v1/chat/completions`

이 경우 MVP 범위는 아래 정도면 충분하다.

- 서버 URL 입력
- 모델 목록 조회
- 채팅 전송/스트리밍 수신
- 최근 대화 저장
- 연결 테스트 버튼

## 소스

- Ollama FAQ: https://docs.ollama.com/faq
- Ollama Authentication: https://docs.ollama.com/api/authentication
- Ollama OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility
- Apple TN3179 Local Network Privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple Cocoa Keys / ATS and NSAllowsLocalNetworking: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html
- Apple WWDC20 Support local network privacy in your app: https://developer.apple.com/videos/play/wwdc2020/10110/
- Apple Tech Talks Adapt to changing network conditions: https://developer.apple.com/videos/play/tech-talks/111378/
- Enchanted App Store: https://apps.apple.com/us/app/enchanted-developers-only/id6474268307
- MyOllama GitHub: https://github.com/bipark/my_ollama_app
- LLM Bridge GitHub: https://github.com/bipark/swift_llm_bridge
- Mocolamma: https://mocolamma.taikun.design/
- Valdis: https://www.valdis.app/
- Open WebUI GitHub: https://github.com/open-webui/open-webui
- Open WebUI + Ollama docs: https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-ollama/
- Tailscale Serve docs: https://tailscale.com/docs/features/tailscale-serve
- Tailscale Funnel docs: https://tailscale.com/docs/features/tailscale-funnel
- Ollama library `llama3.2`: https://ollama.com/library/llama3.2
- Ollama library `qwen3`: https://ollama.com/library/qwen3
