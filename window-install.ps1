<#
.SYNOPSIS
    Claude Code 설치 스크립트 (한글 경로 / 권한 문제 견고 대응)
.DESCRIPTION
    1순위: 공식 네이티브 설치 (Node/npm 불필요, 한글 경로·.npmrc EPERM 회피)
    2순위: npm 폴백 (npm_config_prefix 환경변수로 prefix 설정 → .npmrc 미접촉)
    모든 단계에서 종료 코드를 검사하고, "실제" 설치 위치에서 검증합니다.
    이전 버전의 silent-failure(실패를 성공으로 보고) 버그를 제거했습니다.
#>

# UTF-8 인코딩 + TLS 1.2 (다운로드용)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ============================================================
# ExecutionPolicy 자동 설정 (PSSecurityException 방지)
# ============================================================
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
$policyChanged = $false
if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "Undefined") {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        $policyChanged = $true
    } catch {
        # 실패해도 설치는 계속 (네이티브 .exe 는 실행 정책 영향 없음)
    }
}

# ============================================================
# 출력 / 유틸 함수
# ============================================================
function Write-Step    { param([string]$m) Write-Host "`n▶ $m" -ForegroundColor Yellow }
function Write-Success { param([string]$m) Write-Host "✅ $m" -ForegroundColor Green }
function Write-Err     { param([string]$m) Write-Host "❌ $m" -ForegroundColor Red }
function Write-Info    { param([string]$m) Write-Host "   $m" -ForegroundColor Gray }

function Test-Command { param([string]$c) return $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
function Test-NonAsciiPath { param([string]$p) return $p -match '[^\x00-\x7F]' }

# PATH 새로고침 (레지스트리 최신값을 현재 세션에 반영)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH 영구 추가 (정확 일치 비교 — substring 오탐 방지)
function Add-ToPathPermanent {
    param([string]$NewPath)
    if (-not (Test-Path $NewPath)) { return $false }
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -and ((@($currentPath.Split(';') | Where-Object { $_ -eq $NewPath })).Count -gt 0)) {
        Write-Info "이미 PATH에 존재: $NewPath"
        return $true
    }
    $newPathValue = if ($currentPath) { "$currentPath;$NewPath" } else { $NewPath }
    try {
        [Environment]::SetEnvironmentVariable("Path", $newPathValue, "User")
        $env:Path = "$env:Path;$NewPath"
        Write-Info "PATH 추가됨: $NewPath"
        return $true
    } catch {
        Write-Err "PATH 설정 실패: $_"
        return $false
    }
}

# claude 실행 파일 위치 탐색 (네이티브 → PATH 순)
function Resolve-ClaudePath {
    $candidates = @(
        (Join-Path $env:USERPROFILE ".local\bin\claude.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\claude\claude.exe")
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    Update-Path
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        $src = $cmd.Source
        # .ps1 shim 은 cmd.exe 로 넘기면 메모장(파일 연결)이 떠버림 → 형제 .cmd/.exe 로 치환
        if ($src -like "*.ps1") {
            $dir  = Split-Path $src -Parent
            $base = [System.IO.Path]::GetFileNameWithoutExtension($src)
            foreach ($ext in @(".exe", ".cmd")) {
                $sib = Join-Path $dir ($base + $ext)
                if (Test-Path $sib) { return $sib }
            }
            return $null   # .ps1 뿐이면 폴백 설치로 넘겨 깨끗한 .cmd 를 새로 만든다
        }
        return $src
    }
    return $null
}

# claude 가 행(hang) 없이 실행되는지 검증 (30초 타임아웃 → 설치기가 멈추지 않음)
function Test-ClaudeRuns {
    param([string]$ClaudePath)
    $out = [System.IO.Path]::GetTempFileName()
    $err = "$out.err"
    try {
        if ($ClaudePath -like "*.ps1") {
            # .ps1 을 cmd.exe 로 넘기면 메모장이 뜸 → PowerShell 로 직접 실행
            $p = Start-Process -FilePath "powershell.exe" `
                 -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ClaudePath`" --version" `
                 -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        } else {
            # cmd.exe /c 로 감싸 .exe(네이티브) / .cmd(npm) 양쪽 모두 안전하게 실행
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$ClaudePath`" --version" `
                 -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        }
        if ($p.WaitForExit(30000)) {
            return ((Get-Content $out -Raw -ErrorAction SilentlyContinue) | Out-String).Trim()
        }
        try { $p.Kill() } catch { }
        return $null
    } catch {
        return $null
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }
}

# 직접 다운로드 헬퍼
function Download-File {
    param([string]$Name, [string]$Url, [string]$OutFile)
    Write-Info "$Name 다운로드 중: $Url"
    (New-Object System.Net.WebClient).DownloadFile($Url, $OutFile)
}
function Install-Msi {
    param([string]$Name, [string]$FilePath)
    Write-Info "$Name 설치 중... (관리자 권한 / UAC 팝업이 뜰 수 있습니다)"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$FilePath`" /qn /norestart" -Verb RunAs -Wait
}

# ============================================================
# 설정
# ============================================================
$NpmGlobalPath = "C:\npm-global"          # npm 폴백 시에만 사용
$ClaudeBinPath = "C:\claude-code\bin"     # dsclaude 래퍼

$isVSCode = ($env:TERM_PROGRAM -eq "vscode" -or $env:VSCODE_PID -or $env:VSCODE_CWD)

# ============================================================
# 헤더
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 설치 (한글 경로/권한 대응)  ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($policyChanged) {
    Write-Host "  ✅ PowerShell 보안 정책 자동 설정 완료 (RemoteSigned)" -ForegroundColor Green
    Write-Host ""
}

if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host "  ⚠️  한글 사용자 이름 감지: $env:USERNAME" -ForegroundColor Yellow
    Write-Host "     네이티브 설치로 npm/.npmrc 문제를 회피합니다." -ForegroundColor Gray
    Write-Host ""
}

if ($isVSCode) {
    Write-Host "  💡 VS Code 터미널 감지됨 - 설치 후 PATH를 자동 적용합니다." -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# 1. Git 설치 (선택 — Claude Code 의 Bash 도구용, 없어도 동작)
# ============================================================
Write-Step "Git 확인 중..."
Update-Path
$useWinget = Test-Command "winget"

if (Test-Command "git") {
    Write-Success "Git 이미 설치됨 ($(git --version 2>$null))"
} else {
    if ($useWinget) {
        Write-Info "Git 설치 중... (1-2분)"
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    } else {
        $gitInstaller = "$env:TEMP\Git-installer.exe"
        try {
            Download-File -Name "Git" `
                -Url "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" `
                -OutFile $gitInstaller
            Write-Info "Git 설치 중... (1-2분)"
            Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait | Out-Null
        } catch {
            Write-Info "Git 설치 건너뜀 (선택 사항): $_"
        } finally {
            if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue }
        }
    }
    if (Test-Path "$env:ProgramFiles\Git\cmd") { Add-ToPathPermanent "$env:ProgramFiles\Git\cmd" | Out-Null }
    Update-Path
    if (Test-Command "git") { Write-Success "Git 설치 완료!" } else { Write-Info "Git 미설치 (선택 사항 — 계속 진행)" }
}

# ============================================================
# 2. Claude Code — 공식 네이티브 설치 (1순위)
# ============================================================
Write-Step "Claude Code 설치 중 (공식 네이티브 설치)..."

$claudePath  = Resolve-ClaudePath
$installVia  = $null   # 'native' | 'npm'

if ($claudePath) {
    Write-Success "이미 설치됨: $claudePath"
    $installVia = if ($claudePath -like "*\.local\bin\*") { 'native' } else { 'npm' }
} else {
    Write-Info "irm https://claude.ai/install.ps1 | iex"
    Write-Info "다운로드/설치 중... (1-2분)"
    try {
        $installer = (New-Object System.Net.WebClient).DownloadString('https://claude.ai/install.ps1')
        Invoke-Expression $installer
    } catch {
        Write-Info "네이티브 설치 실패 → npm 폴백으로 전환: $_"
    }
    Update-Path
    $claudePath = Resolve-ClaudePath
    if ($claudePath) {
        $installVia = 'native'
        Write-Success "네이티브 설치 완료: $claudePath"
        Add-ToPathPermanent (Split-Path $claudePath -Parent) | Out-Null
    } else {
        Write-Info "네이티브 설치 미확인 → npm 방식으로 폴백합니다."
    }
}

# ============================================================
# 3. npm 폴백 (네이티브 실패 시에만)
# ============================================================
if (-not $claudePath) {

    # --- 3a. Node.js 확인/설치 ---
    Write-Step "npm 폴백: Node.js 확인 중..."
    Update-Path
    $nodeOk = $false
    try {
        $nodeVer = & cmd.exe /c "node --version" 2>$null
        if ($nodeVer -match "^v(\d+)") { $nodeOk = ([int]$Matches[1] -ge 18) }
    } catch { }

    if (-not $nodeOk) {
        if ($useWinget) {
            Write-Info "Node.js LTS 설치 중... (1-2분)"
            winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
        } else {
            $nodeInstaller = "$env:TEMP\node-lts-installer.msi"
            try {
                Download-File -Name "Node.js" -Url "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $nodeInstaller
                Install-Msi -Name "Node.js" -FilePath $nodeInstaller | Out-Null
            } catch {
                Write-Err "Node.js 설치 실패: $_"
            } finally {
                if (Test-Path $nodeInstaller) { Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue }
            }
        }
        if (Test-Path "$env:ProgramFiles\nodejs") { Add-ToPathPermanent "$env:ProgramFiles\nodejs" | Out-Null }
        Update-Path
        try {
            $nodeVer = & cmd.exe /c "node --version" 2>$null
            $nodeOk = ($nodeVer -match "^v\d+")
        } catch { }
    }

    if ($nodeOk) {
        Write-Success "Node.js 준비됨 ($nodeVer)"
    } else {
        Write-Err "Node.js 를 준비하지 못했습니다. 새 터미널에서 다시 실행하거나 네이티브 설치를 사용하세요."
        Read-Host "Enter를 눌러 종료"
        exit 1
    }

    # --- 3b. npm 전역 경로 설정 (.npmrc 미접촉) ---
    Write-Step "npm 전역 경로 설정 (.npmrc 미접촉 방식)..."
    if (-not (Test-Path $NpmGlobalPath)) {
        New-Item -ItemType Directory -Path $NpmGlobalPath -Force | Out-Null
        Write-Info "디렉토리 생성: $NpmGlobalPath"
    }

    # 혹시 모를 .npmrc read-only/숨김 속성 해제 (EPERM 예방)
    $npmrc = Join-Path $env:USERPROFILE ".npmrc"
    if (Test-Path $npmrc) {
        try { (Get-Item $npmrc -Force).Attributes = 'Normal'; Write-Info ".npmrc 속성 초기화" } catch { }
    }

    # 핵심: 환경변수로 prefix 지정 → npm 이 .npmrc 를 쓰지 않음 (EPERM 원천 회피)
    [Environment]::SetEnvironmentVariable("npm_config_prefix", $NpmGlobalPath, "User")
    $env:npm_config_prefix = $NpmGlobalPath
    Add-ToPathPermanent $NpmGlobalPath | Out-Null
    Write-Info "npm_config_prefix = $NpmGlobalPath (환경변수)"

    # --- 3c. Claude Code 설치 (npm) ---
    Write-Step "Claude Code 설치 중 (npm)..."
    Write-Info "npm install -g @anthropic-ai/claude-code"
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install -g @anthropic-ai/claude-code" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Err "npm 설치 종료 코드: $($proc.ExitCode) (아래에서 실제 위치를 확인합니다)"
    }

    # .ps1 shim 정리 (실행 정책 문제 방지) — 실제 prefix 기준
    $actualPrefix = & cmd.exe /c "npm config get prefix" 2>$null
    if ($actualPrefix) { $actualPrefix = $actualPrefix.Trim() }
    Write-Info "npm 실제 prefix: $actualPrefix"

    if ($actualPrefix) {
        Get-ChildItem -Path $actualPrefix -Filter "claude*.ps1" -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    # --- 3d. 실제 위치에서 검증 ---
    $npmClaude = if ($actualPrefix) { Join-Path $actualPrefix "claude.cmd" } else { $null }
    if ($npmClaude -and (Test-Path $npmClaude)) {
        $claudePath = $npmClaude
        $installVia = 'npm'
        Write-Success "npm 설치 완료: $claudePath"
    } else {
        Write-Err "npm 설치 위치에서 claude.cmd 를 찾지 못했습니다."
        if ($actualPrefix) {
            Write-Info "$actualPrefix 내용:"
            Get-ChildItem $actualPrefix -ErrorAction SilentlyContinue | ForEach-Object { Write-Info "  $($_.Name)" }
        }
    }
}

# ============================================================
# 4. 설치 실패 시 종료
# ============================================================
if (-not $claudePath) {
    Write-Host ""
    Write-Err "Claude Code 설치를 확인하지 못했습니다."
    Write-Host ""
    Write-Host "  수동 설치를 시도해 보세요 (PowerShell):" -ForegroundColor Yellow
    Write-Host "     irm https://claude.ai/install.ps1 | iex" -ForegroundColor White
    Write-Host ""
    Write-Host "  그래도 안 되면 .npmrc 쓰기를 막는 요인을 확인하세요:" -ForegroundColor Yellow
    Write-Host "     - OneDrive 동기화 폴더(문서/홈) 여부" -ForegroundColor Gray
    Write-Host "     - Windows 보안 > 랜섬웨어 방지 > '제어된 폴더 액세스'" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# ============================================================
# 5. dsclaude 래퍼 생성 (권한 스킵 모드)
#    한글 경로를 .cmd 에 직접 박지 않도록 %USERPROFILE% 로 참조 (인코딩 안전)
# ============================================================
Write-Step "dsclaude 래퍼 생성 중..."
if (-not (Test-Path $ClaudeBinPath)) { New-Item -ItemType Directory -Path $ClaudeBinPath -Force | Out-Null }

$nativeExe = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
if ($claudePath -ieq $nativeExe) {
    $launcherForCmd = '"%USERPROFILE%\.local\bin\claude.exe"'   # ASCII 안전
} else {
    $launcherForCmd = "`"$claudePath`""                          # npm: C:\npm-global (ASCII)
}

$dsclaudeContent = @"
@echo off
chcp 65001 >nul 2>&1
$launcherForCmd --dangerously-skip-permissions %*
"@
$dsclaudePath = Join-Path $ClaudeBinPath "dsclaude.cmd"
# Default(=시스템 ANSI/CP949) 인코딩 — cmd.exe 가 배치 파일을 읽는 코드페이지와 일치
Set-Content -Path $dsclaudePath -Value $dsclaudeContent -Encoding Default -Force

if (Test-Path $dsclaudePath) {
    Write-Success "dsclaude.cmd 생성됨: $dsclaudePath"
    Add-ToPathPermanent $ClaudeBinPath | Out-Null
} else {
    Write-Info "dsclaude.cmd 생성 실패 (claude 명령은 정상 사용 가능)"
}

# ============================================================
# 6. 최종 검증 (행 방지 타임아웃 포함)
# ============================================================
Write-Step "설치 검증 중..."
Update-Path
$ver = Test-ClaudeRuns $claudePath
if ($ver) {
    Write-Success "claude 작동 확인: $ver"
} else {
    Write-Info "claude --version 응답 없음/시간초과 — 새 터미널에서 직접 확인하세요."
}

# ============================================================
# 완료 안내
# ============================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  설치 방식 : $installVia" -ForegroundColor White
Write-Host "  claude    : $claudePath" -ForegroundColor Gray
Write-Host "  dsclaude  : 권한 스킵 모드 ($ClaudeBinPath)" -ForegroundColor Gray
Write-Host ""

Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ⚠️  중요 — 'claude' 가 멈춘 것처럼 보이는 이유" -ForegroundColor Yellow
Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  첫 실행 시 'claude' 는 '로그인'을 기다립니다." -ForegroundColor White
Write-Host "  → 화면이 멈춘 게 아니라 브라우저 로그인 대기 상태입니다." -ForegroundColor Gray
Write-Host ""
Write-Host "  올바른 시작 순서:" -ForegroundColor White
Write-Host "     1) Windows Terminal 또는 VS Code 통합 터미널을 새로 연다" -ForegroundColor Cyan
Write-Host "        (팝업으로 뜨는 옛날 PowerShell 창에서는 화면이 깨질 수 있음)" -ForegroundColor DarkGray
Write-Host "     2) claude --version   ← 버전이 뜨면 설치 정상 (안 멈춤)" -ForegroundColor Cyan
Write-Host "     3) claude             ← 안내/브라우저가 뜰 때까지 기다린다" -ForegroundColor Cyan
Write-Host "        브라우저가 안 열리면 화면의 URL을 복사해 로그인" -ForegroundColor DarkGray
Write-Host ""

if ($isVSCode) {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Success "현재 VS Code 터미널 PATH 갱신됨 — 새 터미널 탭에서 'claude' 실행 가능"
    Write-Host "  (안 되면 VS Code 완전 종료 후 재실행)" -ForegroundColor Gray
} else {
    Write-Host "  📌 새 터미널을 열고 위 2~3번을 진행하세요." -ForegroundColor Yellow
}
Write-Host ""
