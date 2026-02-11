# CDP 브라우저 설정 가이드

Claude Code에서 브라우저를 제어할 때, Playwright MCP 대신 CDP 방식을 사용한다.

## 왜 CDP인가

| 방식 | 1회 동작 | 토큰 | 이유 |
|------|---------|------|------|
| Playwright MCP | snapshot → click → snapshot | ~3,000~5,000 | 접근성 트리 수백줄을 매번 왕복 |
| Playwright CLI | `npx playwright screenshot` | ~200~500 | 명령+결과만 |
| **CDP** | `browser nav` + `browser ss` | **~100~300** | 최소 JSON 왕복 |

MCP가 비싼 이유: 매 동작마다 페이지의 **접근성 트리(snapshot)**를 텍스트로 직렬화해서 보내줌. 버튼 하나 클릭하려면 snapshot(수백줄) → ref 찾기 → click → 또 snapshot(수백줄). CDP는 이 과정이 없음.

## CDP란?

**Chrome DevTools Protocol** — 크롬 개발자도구(F12)가 브라우저와 통신하는 프로토콜.

```
평소 (수동):     사람 → F12 → 개발자도구 UI → 브라우저
CDP (자동):      스크립트 → localhost:9222 → 브라우저 직접 제어
```

`--remote-debugging-port=9222`로 Chromium을 실행하면, HTTP/WebSocket으로 F12에서 할 수 있는 모든 것을 코드로 할 수 있다.

---

## 설치

### 1단계: Playwright + Chromium 설치

```bash
npm install -g playwright          # playwright를 글로벌로 설치
npx playwright install chromium    # Chromium 브라우저 다운로드
```

설치 확인:

```bash
npm root -g                        # 글로벌 node_modules 경로 출력되면 OK
# 예: /Users/{username}/.nvm/versions/node/v20.19.0/lib/node_modules

NODE_PATH=$(npm root -g) node -e "require('playwright'); console.log('OK')"
# OK 출력되면 성공
```

### 2단계: ~/.local/bin 디렉토리 준비

```bash
mkdir -p ~/.local/bin
```

PATH에 포함되어 있는지 확인:

```bash
echo $PATH | tr ':' '\n' | grep local/bin
# /Users/{username}/.local/bin 이 출력되어야 함
```

없으면 쉘 설정에 추가:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 3단계: browser 스크립트 설치

아래 내용을 `~/.local/bin/browser` 파일로 저장한다.

> **주의**: 이 프로젝트의 `scripts/browser.sh`는 프로젝트 전용 (PID 경로가 다름).
> 글로벌 사용을 위해서는 반드시 아래 내용을 사용할 것.

```bash
cat > ~/.local/bin/browser << 'EOF'
#!/bin/bash
# 글로벌 CDP 브라우저 관리
# 어떤 프로젝트/디렉토리에서든 사용 가능
# 의존성: node, curl, python3, playwright (npm -g)

set -e

PID_FILE="/tmp/cdp-browser.pid"
CDP_PORT=9222
CDP_URL="http://localhost:$CDP_PORT"

# 글로벌 node_modules 경로 (nvm 환경 지원)
export NODE_PATH="$(npm root -g 2>/dev/null)"

# Playwright Chromium 경로 탐색
CHROMIUM_BIN=$(find ~/Library/Caches/ms-playwright/chromium-*/chrome-mac-arm64/Google\ Chrome\ for\ Testing.app/Contents/MacOS/ -name "Google Chrome for Testing" 2>/dev/null | head -1)
if [ -z "$CHROMIUM_BIN" ]; then
  CHROMIUM_BIN=$(find ~/Library/Caches/ms-playwright/chromium-*/chrome-mac/Google\ Chrome\ for\ Testing.app/Contents/MacOS/ -name "Google Chrome for Testing" 2>/dev/null | head -1)
fi

# --- Playwright connectOverCDP (글로벌 설치) ---
cdp_run() {
  local script="$1"
  node -e "
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.connectOverCDP('$CDP_URL');
  const ctx = browser.contexts()[0] || await browser.newContext();
  const page = ctx.pages()[0] || await ctx.newPage();
  $script
  browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
"
}

case "${1:-help}" in
  start)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Already running (PID: $(cat "$PID_FILE"))"
      echo "CDP: $CDP_URL"
      exit 0
    fi

    existing=$(lsof -ti :$CDP_PORT 2>/dev/null || true)
    if [ -n "$existing" ]; then
      echo "Cleaning port $CDP_PORT"
      echo "$existing" | xargs kill -9 2>/dev/null || true
      sleep 1
    fi

    if [ -z "$CHROMIUM_BIN" ]; then
      echo "Chromium not found. Run: npx playwright install chromium"
      exit 1
    fi

    echo "Starting Chromium (CDP :$CDP_PORT)..."
    "$CHROMIUM_BIN" \
      --headless=new \
      --remote-debugging-port=$CDP_PORT \
      --no-first-run \
      --no-default-browser-check \
      --disable-gpu \
      --window-size=1920,1080 \
      --hide-scrollbars \
      &>/dev/null &

    echo "$!" > "$PID_FILE"

    for i in $(seq 1 15); do
      if curl -s "$CDP_URL/json/version" &>/dev/null; then
        echo "Ready (PID: $(cat "$PID_FILE"))"
        echo "CDP: $CDP_URL"
        exit 0
      fi
      sleep 0.5
    done
    echo "Started but CDP not responding yet"
    ;;

  stop)
    if [ -f "$PID_FILE" ]; then
      pid=$(cat "$PID_FILE")
      kill "$pid" 2>/dev/null && echo "Stopped (PID: $pid)" || true
      rm -f "$PID_FILE"
    fi
    remaining=$(lsof -ti :$CDP_PORT 2>/dev/null || true)
    if [ -n "$remaining" ]; then
      echo "$remaining" | xargs kill -9 2>/dev/null || true
    fi
    echo "Done"
    ;;

  status|st)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Running (PID: $(cat "$PID_FILE"))"
      curl -s "$CDP_URL/json/version" | python3 -c "
import json,sys
v=json.load(sys.stdin)
print(f\"Browser: {v.get('Browser','')}\")" 2>/dev/null
      echo "Tabs:"
      curl -s "$CDP_URL/json" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
  if t.get('type')=='page': print(f\"  {t['url']}\")" 2>/dev/null
    else
      echo "Not running"
    fi
    ;;

  navigate|nav|goto)
    url="${2:?Usage: browser nav <url>}"
    cdp_run "
      await page.goto('$url', { waitUntil: 'domcontentloaded', timeout: 15000 });
      console.log(page.url());
    "
    ;;

  screenshot|ss)
    output="${2:-screenshot-$(date +%s).png}"
    case "$output" in
      /*) ;;
      *) output="$(pwd)/$output" ;;
    esac
    mkdir -p "$(dirname "$output")" 2>/dev/null || true
    cdp_run "
      await page.screenshot({ path: '$output' });
      console.log('$output');
    "
    ;;

  pdf)
    output="${2:-page-$(date +%s).pdf}"
    case "$output" in
      /*) ;;
      *) output="$(pwd)/$output" ;;
    esac
    mkdir -p "$(dirname "$output")" 2>/dev/null || true
    cdp_run "
      await page.pdf({ path: '$output', printBackground: true });
      console.log('$output');
    "
    ;;

  js|eval)
    expr="${2:?Usage: browser js <expression>}"
    cdp_run "
      const result = await page.evaluate(() => { return $expr; });
      console.log(typeof result === 'object' ? JSON.stringify(result, null, 2) : result);
    "
    ;;

  tabs)
    curl -s "$CDP_URL/json" | python3 -c "
import json,sys
for i,t in enumerate(json.load(sys.stdin)):
  if t.get('type')=='page':
    print(f\"[{i}] {t.get('title','')[:40]:40s} {t['url']}\")" 2>/dev/null
    ;;

  *)
    echo "Usage: browser <command> [args]"
    echo ""
    echo "  start              Start headless Chromium"
    echo "  stop               Stop Chromium"
    echo "  status             Show status & tabs"
    echo "  nav <url>          Navigate"
    echo "  ss [file.png]      Screenshot"
    echo "  pdf [file.pdf]     PDF"
    echo "  js <expression>    Run JavaScript"
    echo "  tabs               List tabs"
    echo ""
    echo "CDP: $CDP_URL  PID: $PID_FILE"
    ;;
esac
EOF

chmod +x ~/.local/bin/browser
```

### 4단계: 설치 검증

```bash
# 1. 명령어가 PATH에서 찾아지는지
which browser
# /Users/{username}/.local/bin/browser

# 2. 브라우저 시작
browser start
# Ready (PID: xxxxx)
# CDP: http://localhost:9222

# 3. 페이지 이동 + 스크린샷
browser nav "https://www.google.com"
browser ss /tmp/test.png
# /tmp/test.png

# 4. JS 실행
browser js "document.title"
# Google

# 5. 종료
browser stop
# Done
```

5개 모두 성공하면 설치 완료.

### 5단계: Claude Code 설정 (선택)

Playwright MCP가 설치되어 있다면 제거:

```bash
python3 -c "
import json, os
p = os.path.expanduser('~/.claude.json')
with open(p) as f: d = json.load(f)
if 'playwright' in d.get('mcpServers', {}):
    del d['mcpServers']['playwright']
    with open(p, 'w') as f: json.dump(d, f, indent=2)
    print('Removed playwright MCP')
else:
    print('playwright MCP not found (OK)')
"
```

`~/.claude/CLAUDE.md`에 다음 내용 추가:

```markdown
## Browser: CDP 방식 사용 (Playwright MCP 사용 금지)
- 브라우저 필요 시 `browser start`로 시작
- Playwright MCP 설치 금지 (~/.claude.json의 mcpServers에 playwright 추가 금지)
- 스크린샷은 이미지 파일로 저장 후 Read로 확인
```

---

## 사용법

### 기본 명령어

```bash
browser start              # Chromium 시작 (세션당 한 번)
browser stop               # 종료
browser status             # 상태 + 열린 탭
browser nav <url>          # 페이지 이동
browser ss [file.png]      # 스크린샷
browser pdf [file.pdf]     # PDF 저장
browser js <expression>    # JS 실행
browser tabs               # 탭 목록
```

### 예시

```bash
browser start

# 페이지 이동 + 스크린샷
browser nav "https://github.com"
browser ss github.png

# JS 데이터 추출
browser js "document.title"
browser js "Array.from(document.querySelectorAll('a')).slice(0,5).map(a => a.href)"
browser js "({title: document.title, links: document.querySelectorAll('a').length})"

browser stop
```

### Claude Code에서 node로 직접 제어 (고급)

`browser` 명령어로 부족할 때, node 스크립트로 직접 CDP에 연결:

```js
const { chromium } = require('playwright');
const browser = await chromium.connectOverCDP('http://localhost:9222');
const page = browser.contexts()[0].pages()[0];

await page.goto('https://example.com');
await page.screenshot({ path: 'out.png' });
await page.click('button#submit');
const text = await page.textContent('.result');

browser.close();  // 연결만 해제, 브라우저는 계속 실행
```

---

## Headless / UI 모드

기본은 headless (화면 없음). 디버깅할 때 브라우저 창을 직접 보고 싶으면 UI 모드로 전환 가능.

| 모드 | 플래그 | 화면 | 용도 |
|------|--------|------|------|
| Headless (기본) | `--headless=new` | 안 보임 | 일반 사용, CI |
| UI 모드 | (headless 제거) | 브라우저 창 표시 | 디버깅 |

### 전환 방법

`~/.local/bin/browser`의 start 명령에서 `--headless=new` 줄을 제거하면 UI 모드:

```bash
# headless (기본) — 화면 없음
"$CHROMIUM_BIN" \
  --headless=new \                 # ← 이 줄 제거하면 UI 모드
  --remote-debugging-port=$CDP_PORT \
  ...

# UI 모드 — 브라우저 창이 보임
"$CHROMIUM_BIN" \
  --remote-debugging-port=$CDP_PORT \
  ...
```

### Chromium headless 종류

```bash
--headless=new     # 신형 headless (Chrome 112+, 풀 브라우저 기능, 권장)
--headless         # 구형 headless (일부 기능 제한, 비권장)
(없음)             # UI 모드 — 실제 브라우저 창 표시
```

### 디버깅할 때 UI 모드로 임시 전환

```bash
# 1. headless 종료
browser stop

# 2. UI 모드로 직접 실행
"$(find ~/Library/Caches/ms-playwright/chromium-*/chrome-mac-arm64 \
  -name 'Google Chrome for Testing' 2>/dev/null | head -1)" \
  --remote-debugging-port=9222 \
  --no-first-run \
  --window-size=1920,1080

# 3. 다른 터미널에서 browser 명령어 그대로 사용
browser nav "https://example.com"    # 브라우저 창에서 직접 확인 가능

# 4. 디버깅 끝나면 Ctrl+C로 종료 후 다시 headless
browser start
```

---

## 구조

```
~/.local/bin/browser              # 글로벌 명령어
~/Library/Caches/ms-playwright/   # Chromium 바이너리 (글로벌 캐시)
/tmp/cdp-browser.pid              # 브라우저 PID (글로벌, 프로젝트 무관)
localhost:9222                    # CDP 엔드포인트
```

### 글로벌 vs 프로젝트 스크립트 차이

| | `~/.local/bin/browser` (글로벌) | `scripts/browser.sh` (프로젝트) |
|---|---|---|
| PID 파일 | `/tmp/cdp-browser.pid` | `$PROJECT_DIR/.browser.pid` |
| NODE_PATH | `$(npm root -g)` 설정 | 없음 (프로젝트 node_modules 사용) |
| 사용 범위 | 어떤 디렉토리에서든 | 이 프로젝트 안에서만 |

**글로벌 사용을 위해서는 반드시 `~/.local/bin/browser`를 사용할 것.**

---

## 동작 원리

```
browser start
  └→ Chromium --headless --remote-debugging-port=9222 실행
       └→ localhost:9222 에서 CDP 대기

browser nav "https://..."
  └→ NODE_PATH=(글로벌) node -e "
       const { chromium } = require('playwright');
       browser = await chromium.connectOverCDP('http://localhost:9222');
       page.goto('...');
       browser.close();  // 연결만 해제
     "
  └→ Chromium은 계속 실행 중 (상태 유지)

browser stop
  └→ kill PID → Chromium 종료
```

핵심: `connectOverCDP`는 이미 떠있는 브라우저에 **연결만** 하고, `browser.close()`는 **연결만 해제**. 브라우저는 `browser stop` 할 때까지 계속 살아있다.

### nvm 환경

nvm 사용 시 글로벌 패키지 경로가 버전별로 다르다. 스크립트에 포함된 다음 한 줄이 자동으로 처리:

```bash
export NODE_PATH="$(npm root -g 2>/dev/null)"
```

이 덕분에 `/tmp` 같은 아무 디렉토리에서도 글로벌 `playwright`를 찾을 수 있다.

---

## 트러블슈팅

| 문제 | 해결 |
|------|------|
| `Chromium not found` | `npx playwright install chromium` |
| `Cannot find module 'playwright'` | `npm install -g playwright` |
| `which browser` 안 됨 | `~/.local/bin`이 PATH에 있는지 확인 (2단계) |
| 포트 충돌 | `browser stop` 후 재시작 |
| 브라우저 먹통 | `browser stop && browser start` |
| `no active tab` | `browser start` 먼저 실행 |
| 스크린샷이 이상함 | UI 모드로 전환해서 직접 확인 |
