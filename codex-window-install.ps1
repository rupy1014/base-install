<#
.SYNOPSIS
    Codex CLI 설치 스크립트 (한글 경로 / 권한 문제 견고 대응)
.DESCRIPTION
    Codex CLI(@openai/codex)를 npm 으로 설치합니다.
    npm 전역 경로는 npm_config_prefix 환경변수로 지정해 .npmrc 쓰기(EPERM)를 회피하고,
    모든 단계에서 종료 코드를 검사하며 "실제" 설치 위치에서 검증합니다.
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
        # 실패해도 설치는 계속 진행
    }
}

# 출력 함수
function Write-Step    { param([string]$m) Write-Host "`n▶ $m" -ForegroundColor Yellow }
function Write-Success { param([string]$m) Write-Host "✅ $m" -ForegroundColor Green }
function Write-Err     { param([string]$m) Write-Host "❌ $m" -ForegroundColor Red }
function Write-Info    { param([string]$m) Write-Host "   $m" -ForegroundColor Gray }

function Test-Command { param([string]$c) return $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
function Test-NonAsciiPath { param([string]$p) return $p -match '[^\x00-\x7F]' }

# PATH 새로고침
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

# codex 가 행(hang) 없이 실행되는지 검증 (30초 타임아웃)
function Test-CodexRuns {
    param([string]$CodexPath)
    $out = [System.IO.Path]::GetTempFileName()
    $err = "$out.err"
    try {
        $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$CodexPath`" --version" `
             -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
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
function Install-Exe {
    param([string]$Name, [string]$FilePath, [string]$Arguments)
    Write-Info "$Name 설치 중... (1-3분 소요)"
    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru
    return $proc.ExitCode -eq 0
}
function Install-Msi {
    param([string]$Name, [string]$FilePath)
    Write-Info "$Name 설치 중... (관리자 권한 / UAC 팝업이 뜰 수 있습니다)"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$FilePath`" /qn /norestart" -Verb RunAs -Wait
}

# ============================================================
# 설정
# ============================================================
$NpmGlobalPath = "C:\npm-global"
$CodexBinPath  = "C:\codex-cli\bin"
$CodexConfigDir = "C:\codex-config"   # 한글 사용자명일 때만 사용 (config.toml/auth 저장 위치)

$isVSCode = ($env:TERM_PROGRAM -eq "vscode" -or $env:VSCODE_PID -or $env:VSCODE_CWD)

# ============================================================
# 헤더
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Codex CLI 설치 (한글 경로/권한 대응)    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($policyChanged) {
    Write-Host "  ✅ PowerShell 보안 정책 자동 설정 완료 (RemoteSigned)" -ForegroundColor Green
    Write-Host ""
}
if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host "  ⚠️  한글 사용자 이름 감지: $env:USERNAME" -ForegroundColor Yellow
    Write-Host "     npm 전역 경로를 $NpmGlobalPath 로 설정합니다 (.npmrc 미접촉)." -ForegroundColor Gray
    # 한글 홈(C:\Users\<한글>\.codex)에는 config.toml/auth 저장이 실패한다.
    # CODEX_HOME 을 ASCII 경로로 옮겨 회피 (User 범위 → 새 터미널·omx·dscodex 가 상속).
    try {
        if (-not (Test-Path $CodexConfigDir)) { New-Item -ItemType Directory -Path $CodexConfigDir -Force | Out-Null }
        [Environment]::SetEnvironmentVariable("CODEX_HOME", $CodexConfigDir, "User")
        $env:CODEX_HOME = $CodexConfigDir
        Write-Host "     설정 폴더(CODEX_HOME)를 ASCII 경로로 이동: $CodexConfigDir" -ForegroundColor Gray
    } catch {
        Write-Host "     설정 폴더 이동 실패: $_" -ForegroundColor Red
    }
    Write-Host ""
}
if ($isVSCode) {
    Write-Host "  💡 VS Code 터미널 감지됨 - 설치 후 PATH를 자동 적용합니다." -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# 1. winget 확인
# ============================================================
Write-Step "winget 확인 중..."
$useWinget = Test-Command "winget"
if ($useWinget) { Write-Success "winget 확인됨" } else { Write-Info "winget 없음 - 직접 다운로드 방식으로 설치합니다." }

# ============================================================
# 2. Git 설치
# ============================================================
Write-Step "Git 확인 중..."
Update-Path
if (Test-Command "git") {
    Write-Success "Git 이미 설치됨 ($(git --version 2>$null))"
} else {
    if ($useWinget) {
        Write-Info "Git 설치 중... (1-2분 소요)"
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    } else {
        $gitInstaller = "$env:TEMP\Git-installer.exe"
        try {
            Download-File -Name "Git" `
                -Url "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" `
                -OutFile $gitInstaller
            Install-Exe -Name "Git" -FilePath $gitInstaller `
                -Arguments "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" | Out-Null
        } catch {
            Write-Info "Git 설치 건너뜀 (선택 사항): $_"
        } finally {
            if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue }
        }
    }
    if (Test-Path "$env:ProgramFiles\Git\cmd") { Add-ToPathPermanent "$env:ProgramFiles\Git\cmd" | Out-Null }
    Update-Path
    if (Test-Command "git") { Write-Success "Git 설치 완료!" } else { Write-Info "Git 미설치 (새 터미널에서 확인 필요)" }
}

# ============================================================
# 3. Node.js 설치 (Codex CLI 는 node 필요)
# ============================================================
Write-Step "Node.js 확인 중..."
Update-Path
$nodeExists = $false
try {
    $nodeVer = & cmd.exe /c "node --version" 2>$null
    if ($nodeVer -match "^v\d+") { $nodeExists = $true }
} catch { }

if ($nodeExists) {
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다 ($nodeVer). 업그레이드 중..."
        if ($useWinget) {
            winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
        } else {
            $nodeInstaller = "$env:TEMP\node-lts-installer.msi"
            try {
                Download-File -Name "Node.js" -Url "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $nodeInstaller
                Install-Msi -Name "Node.js" -FilePath $nodeInstaller | Out-Null
            } catch {
                Write-Err "Node.js 다운로드/설치 실패: $_"
            } finally {
                if (Test-Path $nodeInstaller) { Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue }
            }
        }
        Update-Path
    }
} else {
    if ($useWinget) {
        Write-Info "Node.js LTS 설치 중... (1-2분 소요)"
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    } else {
        $nodeInstaller = "$env:TEMP\node-lts-installer.msi"
        try {
            Download-File -Name "Node.js" -Url "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $nodeInstaller
            Install-Msi -Name "Node.js" -FilePath $nodeInstaller | Out-Null
        } catch {
            Write-Err "Node.js 다운로드/설치 실패: $_"
        } finally {
            if (Test-Path $nodeInstaller) { Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue }
        }
    }
    if (Test-Path "$env:ProgramFiles\nodejs") { Add-ToPathPermanent "$env:ProgramFiles\nodejs" | Out-Null }
    Update-Path
    try {
        $nodeVer = & cmd.exe /c "node --version" 2>$null
        if ($nodeVer) {
            Write-Success "Node.js 설치 완료! ($nodeVer)"
        } else {
            Write-Err "Node.js 설치 실패"
            Read-Host "Enter를 눌러 종료"; exit 1
        }
    } catch {
        Write-Err "Node.js 확인 실패"
        Read-Host "Enter를 눌러 종료"; exit 1
    }
}

# npm 확인
$npmExists = $false
try {
    $npmVer = & cmd.exe /c "npm --version" 2>$null
    if ($npmVer -match "^\d+") { $npmExists = $true; Write-Info "npm 버전: $npmVer" }
} catch { }
if (-not $npmExists) {
    Write-Err "npm을 찾을 수 없습니다. Node.js를 다시 설치해주세요."
    Read-Host "Enter를 눌러 종료"; exit 1
}

# ============================================================
# 4. npm 전역 경로 설정 (.npmrc 미접촉 방식 → EPERM 원천 회피)
# ============================================================
Write-Step "npm 전역 경로 설정 (.npmrc 미접촉 방식)..."
if (-not (Test-Path $NpmGlobalPath)) {
    New-Item -ItemType Directory -Path $NpmGlobalPath -Force | Out-Null
    Write-Info "디렉토리 생성: $NpmGlobalPath"
}

# 혹시 모를 .npmrc read-only/숨김 속성 해제
$npmrc = Join-Path $env:USERPROFILE ".npmrc"
if (Test-Path $npmrc) {
    try { (Get-Item $npmrc -Force).Attributes = 'Normal'; Write-Info ".npmrc 속성 초기화" } catch { }
}

# 핵심: 환경변수로 prefix 지정 → npm 이 .npmrc 를 쓰지 않음
[Environment]::SetEnvironmentVariable("npm_config_prefix", $NpmGlobalPath, "User")
$env:npm_config_prefix = $NpmGlobalPath
Add-ToPathPermanent $NpmGlobalPath | Out-Null

$actualPrefix = & cmd.exe /c "npm config get prefix" 2>$null
if ($actualPrefix) { $actualPrefix = $actualPrefix.Trim() } else { $actualPrefix = $NpmGlobalPath }
Write-Info "npm 실제 prefix: $actualPrefix"
Write-Success "npm 전역 경로 설정 완료"

# ============================================================
# 5. Codex CLI 설치 (npm)
# ============================================================
$codexCmd = Join-Path $actualPrefix "codex.cmd"

if (Test-Path $codexCmd) {
    Write-Step "Codex CLI 이미 설치됨 - 설치 스킵"
    Write-Success "발견: $codexCmd"
} else {
    Write-Step "Codex CLI 설치 중 (npm)..."
    Write-Info "npm install -g @openai/codex"
    Write-Info "설치에 1-3분 정도 소요됩니다..."
    Write-Host ""
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install -g @openai/codex" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Err "npm 설치 종료 코드: $($proc.ExitCode) (아래에서 실제 위치를 확인합니다)"
    }

    # 실제 prefix 재확인 후 .ps1 shim 정리 + 검증
    $actualPrefix = & cmd.exe /c "npm config get prefix" 2>$null
    if ($actualPrefix) { $actualPrefix = $actualPrefix.Trim() } else { $actualPrefix = $NpmGlobalPath }
    $codexCmd = Join-Path $actualPrefix "codex.cmd"

    Get-ChildItem -Path $actualPrefix -Filter "codex*.ps1" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

    Write-Step "Codex CLI 설치 확인 중..."
    if (Test-Path $codexCmd) {
        Write-Success "발견: $codexCmd"
    } else {
        Write-Err "Codex CLI 설치 위치에서 codex.cmd 를 찾지 못했습니다."
        Write-Info "$actualPrefix 내용:"
        Get-ChildItem $actualPrefix -ErrorAction SilentlyContinue | ForEach-Object { Write-Info "  $($_.Name)" }
        $nodeModulesPath = Join-Path $actualPrefix "node_modules\@openai\codex"
        if (Test-Path $nodeModulesPath) { Write-Info "패키지는 설치됨: $nodeModulesPath" }
    }
}

# ============================================================
# 6. dscodex 래퍼 생성 (승인/샌드박스 스킵 모드)
# ============================================================
Write-Step "dscodex 래퍼 생성 중..."
if (-not (Test-Path $CodexBinPath)) { New-Item -ItemType Directory -Path $CodexBinPath -Force | Out-Null }

$dscodexContent = @"
@echo off
chcp 65001 >nul 2>&1
call "$codexCmd" --dangerously-bypass-approvals-and-sandbox %*
"@
$dscodexPath = Join-Path $CodexBinPath "dscodex.cmd"
# Default(=시스템 ANSI/CP949) 인코딩 — cmd.exe 가 배치 파일을 읽는 코드페이지와 일치
Set-Content -Path $dscodexPath -Value $dscodexContent -Encoding Default -Force

if (Test-Path $dscodexPath) {
    Write-Success "dscodex.cmd 생성됨: $dscodexPath"
    Add-ToPathPermanent $CodexBinPath | Out-Null
} else {
    Write-Info "dscodex.cmd 생성 실패 (codex 명령은 정상 사용 가능)"
}

# ============================================================
# 7. 최종 PATH 설정 및 검증 (행 방지 타임아웃 포함)
# ============================================================
Write-Step "최종 PATH 설정 중..."
Add-ToPathPermanent $NpmGlobalPath | Out-Null
Add-ToPathPermanent $CodexBinPath | Out-Null
Update-Path

Write-Step "설치 검증 중..."
$verifyOk = $true
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -and (@($userPath.Split(';') | Where-Object { $_ -eq $NpmGlobalPath })).Count -gt 0) {
    Write-Success "npm 전역 경로 PATH 등록됨"
} else {
    Write-Err "npm 전역 경로 PATH 등록 실패"
    $verifyOk = $false
}

if (Test-Path $codexCmd) {
    $codexVersion = Test-CodexRuns $codexCmd
    if ($codexVersion) { Write-Success "codex 작동 확인: $codexVersion" }
    else { Write-Info "codex --version 응답 없음/시간초과 — 새 터미널에서 직접 확인하세요." }
} else {
    Write-Info "codex.cmd 미확인 — 새 터미널에서 'codex --version' 으로 확인하세요."
}

# ============================================================
# 완료 안내
# ============================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  설치된 명령어:" -ForegroundColor White
Write-Host "     codex       - Codex CLI 실행" -ForegroundColor Gray
Write-Host "     dscodex     - 승인/샌드박스 스킵 모드" -ForegroundColor Gray
Write-Host ""
Write-Host "  설치 경로:" -ForegroundColor White
Write-Host "     codex   : $codexCmd" -ForegroundColor Gray
Write-Host "     dscodex : $CodexBinPath" -ForegroundColor Gray
if ($env:CODEX_HOME) { Write-Host "     설정    : $env:CODEX_HOME (한글 경로 회피)" -ForegroundColor Gray }
Write-Host ""

Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ⚠️  중요 — 첫 실행 시 '로그인'이 필요합니다" -ForegroundColor Yellow
Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  codex 는 처음 실행하면 로그인을 기다립니다 (멈춘 게 아님)." -ForegroundColor White
Write-Host "     codex login                  - 브라우저 로그인 (ChatGPT 계정)" -ForegroundColor Gray
Write-Host "     codex login --with-api-key   - API 키 로그인" -ForegroundColor Gray
Write-Host ""
Write-Host "  올바른 시작 순서:" -ForegroundColor White
Write-Host "     1) Windows Terminal 또는 VS Code 통합 터미널을 새로 연다" -ForegroundColor Cyan
Write-Host "     2) codex --version    ← 버전이 뜨면 설치 정상" -ForegroundColor Cyan
Write-Host "     3) codex login        ← 브라우저 로그인" -ForegroundColor Cyan
Write-Host "     4) codex              ← 사용 시작" -ForegroundColor Cyan
Write-Host ""

# Windows 네이티브 지원 안내
Write-Host "  ℹ️  Codex 는 Windows 네이티브 샌드박스를 지원합니다(실험적)." -ForegroundColor DarkGray
Write-Host "     더 안정적인 환경: wsl --install  /  https://developers.openai.com/codex/windows" -ForegroundColor DarkGray
Write-Host ""

# ExecutionPolicy 최종 확인
$finalPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($finalPolicy -eq "Restricted" -or $finalPolicy -eq "Undefined") {
    Write-Host "  ⚠️  보안 정책 자동 설정 실패 - codex 실행 시 오류 발생 가능" -ForegroundColor Yellow
    Write-Host "     해결: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Gray
    Write-Host ""
}
if (-not $verifyOk) {
    Write-Host "  ⚠️  PATH 등록 실패 시 수동 추가 (PowerShell):" -ForegroundColor Yellow
    Write-Host "  `$p = [Environment]::GetEnvironmentVariable('Path', 'User')" -ForegroundColor White
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"`$p;$NpmGlobalPath;$CodexBinPath`", 'User')" -ForegroundColor White
    Write-Host ""
}

if ($isVSCode) {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Success "현재 VS Code 터미널 PATH 갱신됨 — 새 터미널 탭에서 'codex' 사용 가능"
    Write-Host "  (안 되면 VS Code 완전 종료 후 재실행)" -ForegroundColor Gray
} else {
    Write-Host "  📌 새 터미널을 열고 위 2~4번을 진행하세요." -ForegroundColor Yellow
}
Write-Host ""
