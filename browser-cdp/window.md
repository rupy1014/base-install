# CDP 브라우저 설정 가이드 (Windows)

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

```powershell
npm install -g playwright          # playwright를 글로벌로 설치
npx playwright install chromium    # Chromium 브라우저 다운로드
```

설치 확인:

```powershell
npm root -g                        # 글로벌 node_modules 경로 출력되면 OK
# 예: C:\Users\{username}\AppData\Roaming\npm\node_modules

$env:NODE_PATH = (npm root -g); node -e "require('playwright'); console.log('OK')"
# OK 출력되면 성공
```

### 2단계: 스크립트 디렉토리 준비

```powershell
New-Item -ItemType Directory -Force -Path "C:\Users\btsoft\.local\bin"
```

PATH에 포함되어 있는지 확인:

```powershell
$env:PATH -split ';' | Where-Object { $_ -match 'local\\bin' }
# C:\Users\btsoft\.local\bin 이 출력되어야 함
```

없으면 사용자 환경 변수에 추가:

```powershell
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
[Environment]::SetEnvironmentVariable("PATH", "$currentPath;C:\Users\btsoft\.local\bin", "User")
# 터미널 재시작 필요
```

### 3단계: browser.ps1 스크립트 설치

아래 내용을 `C:\Users\btsoft\.local\bin\browser.ps1` 파일로 저장한다.

> **주의**: 이 프로젝트의 `scripts/browser.sh`는 프로젝트 전용 (PID 경로가 다름).
> 글로벌 사용을 위해서는 반드시 아래 내용을 사용할 것.

```powershell
# 글로벌 CDP 브라우저 관리
# 어떤 프로젝트/디렉토리에서든 사용 가능
# 의존성: node, python, playwright (npm -g)

$ErrorActionPreference = 'Stop'

$PID_FILE = "$env:TEMP\cdp-browser.pid"
$CDP_PORT = 9222
$CDP_URL = "http://localhost:$CDP_PORT"

# 글로벌 node_modules 경로
$env:NODE_PATH = (npm root -g 2>$null)

# Playwright Chromium 경로 탐색
$CHROMIUM_BIN = Get-ChildItem -Path "$env:LOCALAPPDATA\ms-playwright\chromium-*\chrome-win\chrome.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

# --- Playwright connectOverCDP (글로벌 설치) ---
function cdp_run {
    param([string]$script)
    node -e @"
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.connectOverCDP('$CDP_URL');
  const ctx = browser.contexts()[0] || await browser.newContext();
  const page = ctx.pages()[0] || await ctx.newPage();
  $script
  browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
"@
}

$command = if ($args.Count -ge 1) { $args[0] } else { "help" }

switch ($command) {
    "start" {
        if ((Test-Path $PID_FILE) -and (Get-Process -Id (Get-Content $PID_FILE) -ErrorAction SilentlyContinue)) {
            $pid = Get-Content $PID_FILE
            Write-Host "Already running (PID: $pid)"
            Write-Host "CDP: $CDP_URL"
            exit 0
        }

        $existing = Get-NetTCPConnection -LocalPort $CDP_PORT -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Cleaning port $CDP_PORT"
            $existing | ForEach-Object {
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 1
        }

        if (-not $CHROMIUM_BIN) {
            Write-Host "Chromium not found. Run: npx playwright install chromium"
            exit 1
        }

        Write-Host "Starting Chromium (CDP :$CDP_PORT)..."
        $proc = Start-Process -FilePath $CHROMIUM_BIN -ArgumentList @(
            "--headless=new",
            "--remote-debugging-port=$CDP_PORT",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-gpu",
            "--window-size=1920,1080",
            "--hide-scrollbars"
        ) -WindowStyle Hidden -PassThru

        Set-Content -Path $PID_FILE -Value $proc.Id

        foreach ($i in 1..15) {
            try {
                $null = Invoke-RestMethod -Uri "$CDP_URL/json/version" -ErrorAction Stop
                $pid = Get-Content $PID_FILE
                Write-Host "Ready (PID: $pid)"
                Write-Host "CDP: $CDP_URL"
                exit 0
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }
        Write-Host "Started but CDP not responding yet"
    }

    "stop" {
        if (Test-Path $PID_FILE) {
            $pid = Get-Content $PID_FILE
            try {
                Stop-Process -Id $pid -ErrorAction Stop
                Write-Host "Stopped (PID: $pid)"
            } catch {
                # 이미 종료됨
            }
            Remove-Item -Path $PID_FILE -Force
        }
        $remaining = Get-NetTCPConnection -LocalPort $CDP_PORT -ErrorAction SilentlyContinue
        if ($remaining) {
            $remaining | ForEach-Object {
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "Done"
    }

    { $_ -in "status", "st" } {
        if ((Test-Path $PID_FILE) -and (Get-Process -Id (Get-Content $PID_FILE) -ErrorAction SilentlyContinue)) {
            $pid = Get-Content $PID_FILE
            Write-Host "Running (PID: $pid)"
            try {
                $version = Invoke-RestMethod -Uri "$CDP_URL/json/version" -ErrorAction Stop
                Write-Host "Browser: $($version.Browser)"
            } catch {}
            Write-Host "Tabs:"
            try {
                $tabs = Invoke-RestMethod -Uri "$CDP_URL/json" -ErrorAction Stop
                $tabs | Where-Object { $_.type -eq 'page' } | ForEach-Object {
                    Write-Host "  $($_.url)"
                }
            } catch {}
        } else {
            Write-Host "Not running"
        }
    }

    { $_ -in "navigate", "nav", "goto" } {
        if ($args.Count -lt 2) {
            Write-Host "Usage: browser.ps1 nav <url>"
            exit 1
        }
        $url = $args[1]
        cdp_run @"
      await page.goto('$url', { waitUntil: 'domcontentloaded', timeout: 15000 });
      console.log(page.url());
"@
    }

    { $_ -in "screenshot", "ss" } {
        $timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $output = if ($args.Count -ge 2) { $args[1] } else { "screenshot-$timestamp.png" }
        if (-not [System.IO.Path]::IsPathRooted($output)) {
            $output = Join-Path (Get-Location) $output
        }
        $dir = Split-Path $output -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        cdp_run @"
      await page.screenshot({ path: '$($output -replace '\\','\\\\')' });
      console.log('$($output -replace '\\','\\\\')');
"@
    }

    "pdf" {
        $timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $output = if ($args.Count -ge 2) { $args[1] } else { "page-$timestamp.pdf" }
        if (-not [System.IO.Path]::IsPathRooted($output)) {
            $output = Join-Path (Get-Location) $output
        }
        $dir = Split-Path $output -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        cdp_run @"
      await page.pdf({ path: '$($output -replace '\\','\\\\')' , printBackground: true });
      console.log('$($output -replace '\\','\\\\')');
"@
    }

    { $_ -in "js", "eval" } {
        if ($args.Count -lt 2) {
            Write-Host "Usage: browser.ps1 js <expression>"
            exit 1
        }
        $expr = $args[1]
        cdp_run @"
      const result = await page.evaluate(() => { return $expr; });
      console.log(typeof result === 'object' ? JSON.stringify(result, null, 2) : result);
"@
    }

    "tabs" {
        try {
            $tabs = Invoke-RestMethod -Uri "$CDP_URL/json" -ErrorAction Stop
            $i = 0
            $tabs | Where-Object { $_.type -eq 'page' } | ForEach-Object {
                $title = if ($_.title.Length -gt 40) { $_.title.Substring(0, 40) } else { $_.title.PadRight(40) }
                Write-Host "[$i] $title $($_.url)"
                $i++
            }
        } catch {
            Write-Host "Cannot connect to CDP. Is the browser running?"
        }
    }

    default {
        Write-Host "Usage: browser.ps1 <command> [args]"
        Write-Host ""
        Write-Host "  start              Start headless Chromium"
        Write-Host "  stop               Stop Chromium"
        Write-Host "  status             Show status & tabs"
        Write-Host "  nav <url>          Navigate"
        Write-Host "  ss [file.png]      Screenshot"
        Write-Host "  pdf [file.pdf]     PDF"
        Write-Host "  js <expression>    Run JavaScript"
        Write-Host "  tabs               List tabs"
        Write-Host ""
        Write-Host "CDP: $CDP_URL  PID: $PID_FILE"
    }
}
```

> **참고**: Windows에서는 `chmod +x`가 불필요하다. PowerShell 스크립트는 확장자(`.ps1`)로 실행된다.

### 4단계: 설치 검증

```powershell
# 1. 명령어가 PATH에서 찾아지는지
Get-Command browser.ps1
# C:\Users\btsoft\.local\bin\browser.ps1

# 2. 브라우저 시작
browser.ps1 start
# Ready (PID: xxxxx)
# CDP: http://localhost:9222

# 3. 페이지 이동 + 스크린샷
browser.ps1 nav "https://www.google.com"
browser.ps1 ss "$env:TEMP\test.png"
# C:\Users\btsoft\AppData\Local\Temp\test.png

# 4. JS 실행
browser.ps1 js "document.title"
# Google

# 5. 종료
browser.ps1 stop
# Done
```

5개 모두 성공하면 설치 완료.

### 5단계: Claude Code 설정 (선택)

Playwright MCP가 설치되어 있다면 제거:

```powershell
python -c @"
import json, os
p = os.path.expanduser('~/.claude.json')
with open(p) as f: d = json.load(f)
if 'playwright' in d.get('mcpServers', {}):
    del d['mcpServers']['playwright']
    with open(p, 'w') as f: json.dump(d, f, indent=2)
    print('Removed playwright MCP')
else:
    print('playwright MCP not found (OK)')
"@
```

`C:\Users\btsoft\.claude\CLAUDE.md`에 다음 내용 추가:

```markdown
## Browser: CDP 방식 사용 (Playwright MCP 사용 금지)
- 브라우저 필요 시 `browser.ps1 start`로 시작
- Playwright MCP 설치 금지 (~/.claude.json의 mcpServers에 playwright 추가 금지)
- 스크린샷은 이미지 파일로 저장 후 Read로 확인
```

---

## 사용법

### 기본 명령어

```powershell
browser.ps1 start              # Chromium 시작 (세션당 한 번)
browser.ps1 stop               # 종료
browser.ps1 status             # 상태 + 열린 탭
browser.ps1 nav <url>          # 페이지 이동
browser.ps1 ss [file.png]      # 스크린샷
browser.ps1 pdf [file.pdf]     # PDF 저장
browser.ps1 js <expression>    # JS 실행
browser.ps1 tabs               # 탭 목록
```

### 예시

```powershell
browser.ps1 start

# 페이지 이동 + 스크린샷
browser.ps1 nav "https://github.com"
browser.ps1 ss github.png

# JS 데이터 추출
browser.ps1 js "document.title"
browser.ps1 js "Array.from(document.querySelectorAll('a')).slice(0,5).map(a => a.href)"
browser.ps1 js "({title: document.title, links: document.querySelectorAll('a').length})"

browser.ps1 stop
```

### Claude Code에서 node로 직접 제어 (고급)

`browser.ps1` 명령어로 부족할 때, node 스크립트로 직접 CDP에 연결:

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

`C:\Users\btsoft\.local\bin\browser.ps1`의 start 명령에서 `"--headless=new"` 항목을 제거하면 UI 모드:

```powershell
# headless (기본) -- 화면 없음
$proc = Start-Process -FilePath $CHROMIUM_BIN -ArgumentList @(
    "--headless=new",                   # <-- 이 줄 제거하면 UI 모드
    "--remote-debugging-port=$CDP_PORT",
    ...
) -WindowStyle Hidden -PassThru

# UI 모드 -- 브라우저 창이 보임
$proc = Start-Process -FilePath $CHROMIUM_BIN -ArgumentList @(
    "--remote-debugging-port=$CDP_PORT",
    ...
) -PassThru                             # WindowStyle Hidden도 제거
```

### Chromium headless 종류

```
--headless=new     # 신형 headless (Chrome 112+, 풀 브라우저 기능, 권장)
--headless         # 구형 headless (일부 기능 제한, 비권장)
(없음)             # UI 모드 -- 실제 브라우저 창 표시
```

### 디버깅할 때 UI 모드로 임시 전환

```powershell
# 1. headless 종료
browser.ps1 stop

# 2. Chromium 경로 찾기
$chromium = Get-ChildItem -Path "$env:LOCALAPPDATA\ms-playwright\chromium-*\chrome-win\chrome.exe" | Select-Object -First 1 -ExpandProperty FullName

# 3. UI 모드로 직접 실행
Start-Process -FilePath $chromium -ArgumentList @(
    "--remote-debugging-port=9222",
    "--no-first-run",
    "--window-size=1920,1080"
)

# 4. 다른 터미널에서 browser.ps1 명령어 그대로 사용
browser.ps1 nav "https://example.com"    # 브라우저 창에서 직접 확인 가능

# 5. 디버깅 끝나면 브라우저 창 닫고 다시 headless
browser.ps1 stop
browser.ps1 start
```

---

## 구조

```
C:\Users\btsoft\.local\bin\browser.ps1        # 글로벌 명령어
%LOCALAPPDATA%\ms-playwright\                 # Chromium 바이너리 (글로벌 캐시)
%TEMP%\cdp-browser.pid                        # 브라우저 PID (글로벌, 프로젝트 무관)
localhost:9222                                # CDP 엔드포인트
```

### 글로벌 vs 프로젝트 스크립트 차이

| | `C:\Users\btsoft\.local\bin\browser.ps1` (글로벌) | `scripts\browser.sh` (프로젝트) |
|---|---|---|
| PID 파일 | `%TEMP%\cdp-browser.pid` | `$PROJECT_DIR\.browser.pid` |
| NODE_PATH | `$(npm root -g)` 설정 | 없음 (프로젝트 node_modules 사용) |
| 사용 범위 | 어떤 디렉토리에서든 | 이 프로젝트 안에서만 |

**글로벌 사용을 위해서는 반드시 `C:\Users\btsoft\.local\bin\browser.ps1`를 사용할 것.**

---

## 동작 원리

```
browser.ps1 start
  └→ Chromium --headless --remote-debugging-port=9222 실행
       └→ localhost:9222 에서 CDP 대기

browser.ps1 nav "https://..."
  └→ NODE_PATH=(글로벌) node -e "
       const { chromium } = require('playwright');
       browser = await chromium.connectOverCDP('http://localhost:9222');
       page.goto('...');
       browser.close();  // 연결만 해제
     "
  └→ Chromium은 계속 실행 중 (상태 유지)

browser.ps1 stop
  └→ Stop-Process PID → Chromium 종료
```

핵심: `connectOverCDP`는 이미 떠있는 브라우저에 **연결만** 하고, `browser.close()`는 **연결만 해제**. 브라우저는 `browser.ps1 stop` 할 때까지 계속 살아있다.

### nvm-windows / fnm 환경

nvm-windows 또는 fnm 사용 시 글로벌 패키지 경로가 버전별로 다를 수 있다. 스크립트에 포함된 다음 한 줄이 자동으로 처리:

```powershell
$env:NODE_PATH = (npm root -g 2>$null)
```

이 덕분에 어떤 디렉토리에서도 글로벌 `playwright`를 찾을 수 있다.

---

## 트러블슈팅

| 문제 | 해결 |
|------|------|
| `Chromium not found` | `npx playwright install chromium` |
| `Cannot find module 'playwright'` | `npm install -g playwright` |
| `Get-Command browser.ps1` 안 됨 | `C:\Users\btsoft\.local\bin`이 PATH에 있는지 확인 (2단계) |
| 포트 충돌 | `browser.ps1 stop` 후 재시작 |
| 브라우저 먹통 | `browser.ps1 stop; browser.ps1 start` |
| `no active tab` | `browser.ps1 start` 먼저 실행 |
| 스크린샷이 이상함 | UI 모드로 전환해서 직접 확인 |
| 실행 정책 오류 | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| `Start-Process` 권한 오류 | 관리자 권한 PowerShell에서 실행 |
| `%LOCALAPPDATA%` 경로 못 찾음 | `$env:LOCALAPPDATA` 로 확인 (보통 `C:\Users\{username}\AppData\Local`) |
