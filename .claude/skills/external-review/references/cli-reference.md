# agy / grok CLI 레퍼런스

> `external-review.sh`가 호출을 표준화하므로, 보통은 이 파일을 읽을 필요가 없다.
> 스크립트가 못 다루는 플래그를 직접 써야 할 때만 참조한다. (출처: 각 CLI `--help`, 확인일 2026-06-05)

## agy (Gemini CLI)

Claude Code 류 agentic CLI. 헤드리스 단일 프롬프트 모드가 핵심.

| 플래그 | 의미 |
|---|---|
| `-p`, `--print`, `--prompt` | 단일 프롬프트 비대화형 실행 후 stdout 출력 |
| `--model <id>` | 세션 모델 |
| `--add-dir <dir>` | 워크스페이스에 디렉토리 추가(repeatable) — cwd 밖 파일 접근 |
| `--print-timeout <dur>` | print 모드 대기 타임아웃(기본 `5m`) |
| `--dangerously-skip-permissions` | 도구 권한 프롬프트 자동 승인(헤드리스 진행용) |
| `-c`, `--continue` | 최근 대화 이어가기 |
| `--conversation <id>` | 특정 대화 재개 |
| `--sandbox` | 터미널 제한 샌드박스 |
| `-i`, `--prompt-interactive` | 초기 프롬프트 후 대화 지속 |

서브커맨드: `models`(모델 목록), `changelog`, `install`, `plugin`, `update`.

호출 형태:
```bash
agy -p "<프롬프트>" --add-dir "$(pwd)" --print-timeout 15m --dangerously-skip-permissions [--model <id>]
```

> 주의: `agy`에는 effort/self-check/best-of-n 같은 엄중도 플래그가 **없다**. 엄중도는 프롬프트로만 조절한다.

## grok (Grok Build TUI)

Rust 기반. 기본은 TUI(대화형), 헤드리스는 `-p`/`--single` 또는 `agent` 서브커맨드.

| 플래그 | 의미 |
|---|---|
| `-p`, `--single <PROMPT>` | 단일 프롬프트 → stdout 출력 후 종료(헤드리스) |
| `--prompt-file <path>` | 파일에서 프롬프트 |
| `--prompt-json <json>` | content block JSON 프롬프트 |
| `--output-format <fmt>` | `plain`(기본) / `json` / `streaming-json` |
| `-m`, `--model <id>` | 모델 |
| `--effort <level>` | `low` / `medium` / `high` / `xhigh` / `max` |
| `--reasoning-effort <e>` | 추론 모델용 추론 노력 |
| `--check` | 자기검증 루프 프롬프트 추가(헤드리스 전용) |
| `--best-of-n <N>` | N개 병렬 실행 후 최선 선택(헤드리스 전용) |
| `--cwd <dir>` | 작업 디렉토리 |
| `--permission-mode <m>` | `default`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`/`plan` |
| `--tools <list>` / `--disallowed-tools <list>` | 도구 허용/제거(comma-separated) |
| `--sandbox <profile>` | 파일·네트워크 샌드박스(env `GROK_SANDBOX`) |
| `--rules <rules>` | 시스템 프롬프트에 규칙 추가 |
| `--system-prompt-override <p>` | 시스템 프롬프트 교체 |
| `--verbatim` | 프롬프트를 그대로 전송 |
| `--disable-web-search` | 웹 검색/패치 비활성화 |
| `-c`, `--continue` / `-r`, `--resume [id]` | 세션 이어가기/재개 |
| `-w`, `--worktree [name]` | 새 git worktree에서 세션 시작 |

서브커맨드: `agent`(UI 없이 실행), `models`, `sessions`, `login`/`logout`, `inspect`, `export`, `mcp`, `memory`, `update`.

호출 형태(엄중 리뷰):
```bash
grok -p "<프롬프트>" --cwd "$(pwd)" --output-format plain --permission-mode dontAsk \
  --effort high --check [-m <id>]
# 최고강도: --effort xhigh --best-of-n 3
```

## 권한·읽기 전용 메모
- 리뷰는 읽기만 필요. 권한 자동승인 플래그는 "팝업 없이 진행"용이고, 실제 읽기 전용 보장은 **프롬프트 지시**가 한다.
- 더 강한 격리가 필요하면 grok `--permission-mode plan`(변경 차단) 또는 `--sandbox`, `--disallowed-tools`로 편집 도구 제거를 검토. 단 과한 제한은 리뷰어의 사실 확인(빌드 설정 조회 등)을 막을 수 있다.

## 모델 목록 확인
```bash
agy models        # Gemini 사용 가능 모델
grok models       # Grok 사용 가능 모델
```
(네트워크/인증이 필요할 수 있음. 모델 미지정 시 각 CLI 기본 모델 사용.)
