<#
.SYNOPSIS
    oh-my-codex (OMX) 설치 스크립트 (Windows)
.DESCRIPTION
    Codex CLI 설치 이후 oh-my-codex와 dscodex alias를 설정합니다.
#>

# UTF-8 인코딩
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 출력 함수
function Write-Step { param([string]$Message) Write-Host "`n▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }

function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# PATH 새로고침
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH에 영구 추가
function Add-ToPathPermanent {
    param([string]$NewPath)
    if (-not (Test-Path $NewPath)) { return $false }
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -like "*$NewPath*") {
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
        Write-Error-Custom "PATH 설정 실패: $_"
        return $false
    }
}

# VS Code 터미널 감지
$isVSCode = $false
if ($env:TERM_PROGRAM -eq "vscode" -or $env:VSCODE_PID -or $env:VSCODE_CWD) {
    $isVSCode = $true
}

# ============================================================
# 설정
# ============================================================

$NpmGlobalPath = "C:\npm-global"
$CodexBinPath = "C:\codex-cli\bin"

# ============================================================
# 메인
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   oh-my-codex (OMX) 설치 (Windows)      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 사전 요구사항 확인
# ============================================================
Write-Step "사전 요구사항 확인 중..."

Update-Path

# Node.js 확인
$nodeExists = $false
try {
    $nodeVer = & cmd.exe /c "node --version" 2>$null
    if ($nodeVer -match "^v\d+") {
        $nodeExists = $true
        $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
        if ($versionNum -lt 20) {
            Write-Error-Custom "Node.js 20+ 필요 (현재: $nodeVer)"
            Write-Info "Node.js를 업그레이드하세요."
            Read-Host "Enter를 눌러 종료"
            exit 1
        }
        Write-Success "Node.js $nodeVer"
    }
} catch { }

if (-not $nodeExists) {
    Write-Error-Custom "Node.js가 설치되어 있지 않습니다."
    Write-Info "먼저 codex-window-install.ps1 을 실행하세요."
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# npm 확인
$npmExists = $false
try {
    $npmVer = & cmd.exe /c "npm --version" 2>$null
    if ($npmVer -match "^\d+") {
        $npmExists = $true
        Write-Success "npm $npmVer"
    }
} catch { }

if (-not $npmExists) {
    Write-Error-Custom "npm이 설치되어 있지 않습니다."
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# Codex CLI 확인
$codexCmd = "$NpmGlobalPath\codex.cmd"
$codexExists = (Test-Path $codexCmd) -or (Test-Command "codex")
if ($codexExists) {
    try {
        $codexVer = & cmd.exe /c "codex --version" 2>$null
        Write-Success "Codex CLI $codexVer"
    } catch {
        Write-Success "Codex CLI installed"
    }
} else {
    Write-Error-Custom "Codex CLI가 설치되어 있지 않습니다."
    Write-Info "먼저 codex-window-install.ps1 을 실행하세요."
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# ============================================================
# 2. oh-my-codex 설치
# ============================================================
Write-Step "oh-my-codex 설치 중..."

$omxCmd = "$NpmGlobalPath\omx.cmd"
$omxExists = Test-Path $omxCmd

if ($omxExists) {
    Write-Success "oh-my-codex 이미 설치됨: $omxCmd"
} else {
    Write-Info "npm install -g oh-my-codex"
    Write-Info "설치에 1-2분 정도 소요됩니다..."
    Write-Host ""

    $installProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install -g oh-my-codex" -Wait -PassThru -NoNewWindow

    if ($installProcess.ExitCode -eq 0) {
        Write-Success "oh-my-codex 설치 완료!"
    } else {
        Write-Info "npm 설치 종료 코드: $($installProcess.ExitCode)"
        Write-Info "계속 진행합니다..."
    }

    # .ps1 파일 정리 (실행 정책 문제 방지)
    $ps1Files = Get-ChildItem -Path $NpmGlobalPath -Filter "omx*.ps1" -ErrorAction SilentlyContinue
    if ($ps1Files) {
        foreach ($file in $ps1Files) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-Info "삭제됨: $($file.Name)"
        }
    }
}

# ============================================================
# 3. psmux 설치 (team 모드용, Windows)
# ============================================================
Write-Step "psmux 확인 중 (team 모드용)..."

if (Test-Command "winget") {
    try {
        $psmuxInstalled = winget list --name psmux 2>$null
        if ($psmuxInstalled -match "psmux") {
            Write-Success "psmux 설치됨"
        } else {
            Write-Info "psmux 설치 중..."
            winget install psmux --accept-package-agreements --accept-source-agreements --silent 2>$null
            Write-Success "psmux 설치 완료!"
        }
    } catch {
        Write-Info "psmux 설치 실패 - team 모드 없이도 기본 기능은 사용 가능"
    }
} else {
    Write-Info "winget 없음 - psmux 수동 설치 필요: winget install psmux"
}

# ============================================================
# 4. omx setup 실행
# ============================================================
Write-Step "omx setup 실행 중..."

Update-Path

if (Test-Path $omxCmd) {
    try {
        & cmd.exe /c "omx setup" 2>$null
        Write-Success "omx setup 완료!"
    } catch {
        Write-Info "omx setup 실행 중 오류 (계속 진행)"
    }
} elseif (Test-Command "omx") {
    try {
        omx setup 2>$null
        Write-Success "omx setup 완료!"
    } catch {
        Write-Info "omx setup 실행 중 오류 (계속 진행)"
    }
} else {
    Write-Info "omx 명령어를 찾을 수 없어 setup 스킵"
}

# ============================================================
# 5. dscodex 래퍼 생성 (omx --madmax --high)
# ============================================================
Write-Step "dscodex 래퍼 생성 중..."

if (-not (Test-Path $CodexBinPath)) {
    New-Item -ItemType Directory -Path $CodexBinPath -Force | Out-Null
}

# dscodex.cmd 생성 (omx --madmax --high)
$dscodexContent = @"
@echo off
chcp 65001 >nul 2>&1
"$NpmGlobalPath\omx.cmd" --madmax --high %*
"@

$dscodexPath = "$CodexBinPath\dscodex.cmd"
Set-Content -Path $dscodexPath -Value $dscodexContent -Encoding ASCII -Force

if (Test-Path $dscodexPath) {
    Write-Success "dscodex.cmd 생성됨: $dscodexPath"
    Add-ToPathPermanent $CodexBinPath | Out-Null
} else {
    Write-Error-Custom "dscodex.cmd 생성 실패"
}

# PowerShell 프로필에 alias 추가
Write-Step "PowerShell alias 설정 중..."

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$aliasLine = "function dscodex { omx --madmax --high `$args }"
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue

if ($profileContent -notlike "*function dscodex*") {
    Add-Content -Path $PROFILE -Value "`n# dscodex: omx madmax shortcut`n$aliasLine"
    Write-Success "PowerShell 프로필에 dscodex alias 추가됨"
} else {
    Write-Info "dscodex alias 이미 존재"
}

# 현재 세션에도 적용
Invoke-Expression $aliasLine
Write-Success "현재 세션에 dscodex alias 적용됨"

# ============================================================
# 6. 최종 PATH 설정 및 확인
# ============================================================
Write-Step "최종 설정 중..."

Add-ToPathPermanent $NpmGlobalPath | Out-Null
Add-ToPathPermanent $CodexBinPath | Out-Null
Update-Path

# ============================================================
# 7. 설치 검증
# ============================================================
Write-Step "설치 검증 중..."

$verifyOk = $true

# omx 확인
Write-Info "omx 명령어 테스트..."
try {
    $omxVersion = & cmd.exe /c "omx --version" 2>$null
    if ($omxVersion) {
        Write-Success "omx 명령어 작동: $omxVersion"
    } else {
        Write-Info "omx 응답 없음 (새 터미널에서 확인 필요)"
    }
} catch {
    Write-Info "omx 테스트 실패 (새 터미널에서 확인 필요)"
}

# dscodex.cmd 확인
if (Test-Path "$CodexBinPath\dscodex.cmd") {
    Write-Success "dscodex.cmd 확인됨"
} else {
    Write-Error-Custom "dscodex.cmd 없음"
    $verifyOk = $false
}

# PowerShell alias 확인
if ((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue) -like "*function dscodex*") {
    Write-Success "PowerShell dscodex alias 확인됨"
} else {
    Write-Error-Custom "PowerShell dscodex alias 누락"
    $verifyOk = $false
}

# ============================================================
# 완료
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║         OMX 설치 완료! 🎉                ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "  사용 가능한 명령어:" -ForegroundColor White
Write-Host "     dscodex     - omx --madmax --high (풀파워 모드)" -ForegroundColor Gray
Write-Host "     omx         - oh-my-codex 기본 실행" -ForegroundColor Gray
Write-Host "     codex       - Codex CLI 기본 실행" -ForegroundColor Gray
Write-Host ""
Write-Host "  OMX 워크플로우:" -ForegroundColor White
Write-Host "     dscodex 로 시작한 뒤:" -ForegroundColor Gray
Write-Host '     $deep-interview "작업 내용 명확화"' -ForegroundColor Gray
Write-Host '     $ralplan "구현 계획 승인"' -ForegroundColor Gray
Write-Host '     $ralph "승인된 계획 실행"' -ForegroundColor Gray
Write-Host '     $team 3:executor "병렬 실행"' -ForegroundColor Gray
Write-Host ""

if ($isVSCode) {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Success "현재 터미널 세션의 PATH가 갱신되었습니다."
    Write-Host ""
    Write-Host "  지금 바로 dscodex 를 실행해보세요!" -ForegroundColor Green
    Write-Host "  (안 되면 VS Code를 완전히 재시작하세요)" -ForegroundColor Gray
} else {
    Write-Host "  📌 새 PowerShell/터미널 창을 열어주세요!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  3초 후 새 PowerShell이 열립니다..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3

    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Clear-Host; Write-Host '✅ OMX 준비 완료!' -ForegroundColor Green; Write-Host ''; Write-Host '아래 명령어를 입력하세요:' -ForegroundColor White; Write-Host ''; Write-Host '  dscodex     - omx --madmax --high (풀파워)' -ForegroundColor Cyan; Write-Host '  omx         - oh-my-codex 기본' -ForegroundColor Cyan; Write-Host '  codex       - Codex CLI 기본' -ForegroundColor Cyan; Write-Host ''"

    Write-Host ""
    Write-Host "  새 PowerShell 창에서 dscodex 를 입력하세요!" -ForegroundColor Green
}

Write-Host ""
