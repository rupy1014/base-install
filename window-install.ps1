<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치하고 PATH 설정까지 완료합니다.
    dsclaude 명령어도 함께 설치됩니다.
#>

# 콘솔 출력 함수
function Write-Step { param([string]$Message) Write-Host "▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# PATH 새로고침 (시스템 + 사용자)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH에 경로 추가 (영구적 + 현재 세션)
function Add-ToPath {
    param([string]$NewPath)
    
    if (-not (Test-Path $NewPath)) { return }
    
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentUserPath -notlike "*$NewPath*") {
        $newUserPath = "$currentUserPath;$NewPath"
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Info "PATH에 추가됨: $NewPath"
    }
    
    # 현재 세션에도 적용
    if ($env:Path -notlike "*$NewPath*") {
        $env:Path = "$env:Path;$NewPath"
    }
}

# dsclaude 명령어 생성 (.cmd만 사용 - 실행정책 문제 회피)
function Install-DsClaude {
    Write-Step "dsclaude 명령어 생성 중..."
    
    # 저장할 디렉토리 (사용자 로컬 bin)
    $binPath = "$env:USERPROFILE\.local\bin"
    
    if (-not (Test-Path $binPath)) {
        New-Item -ItemType Directory -Path $binPath -Force | Out-Null
    }
    
    # 기존 .ps1 파일 제거 (실행정책 충돌 방지)
    $oldPs1 = "$binPath\dsclaude.ps1"
    if (Test-Path $oldPs1) {
        Remove-Item $oldPs1 -Force
        Write-Info "기존 dsclaude.ps1 제거됨 (실행정책 문제 방지)"
    }
    
    # dsclaude.cmd 파일 생성 (실행정책 영향 안받음)
    $dsclaudeCmd = @"
@echo off
claude --dangerously-skip-permissions %*
"@
    
    $cmdPath = "$binPath\dsclaude.cmd"
    Set-Content -Path $cmdPath -Value $dsclaudeCmd -Encoding ASCII
    
    # PATH에 추가
    Add-ToPath $binPath
    
    if (Test-Path $cmdPath) {
        Write-Success "dsclaude 명령어 생성 완료!"
        Write-Info "위치: $cmdPath"
    } else {
        Write-Error-Custom "dsclaude 생성 실패"
    }
}

# ============================================================
# 메인 설치
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 원클릭 설치 스크립트       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. winget 확인
Write-Step "winget 확인 중..."
if (-not (Test-Command "winget")) {
    Write-Error-Custom "winget이 설치되어 있지 않습니다."
    Write-Info "Windows 10 1709 이상 또는 Windows 11이 필요합니다."
    Write-Info "Microsoft Store에서 'App Installer'를 설치해주세요."
    Read-Host "Enter 키를 눌러 종료"
    exit 1
}
Write-Success "winget 확인됨"

# 2. Git 설치
Write-Host ""
Write-Step "Git 확인 중..."
Update-Path
if (Test-Command "git") {
    $gitVer = git --version 2>$null
    Write-Success "Git 이미 설치됨 ($gitVer)"
} else {
    Write-Info "Git 설치 중... (1-2분 소요)"
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
    
    # Git 경로 추가
    $gitPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin",
        "${env:ProgramFiles(x86)}\Git\cmd"
    )
    foreach ($p in $gitPaths) {
        if (Test-Path $p) { Add-ToPath $p }
    }
    
    Update-Path
    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Error-Custom "Git 설치 실패 - 새 터미널에서 확인 필요"
    }
}

# 3. Node.js 설치
Write-Host ""
Write-Step "Node.js 확인 중..."
Update-Path
if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다 ($nodeVer). 업그레이드 중..."
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
        Update-Path
    }
} else {
    Write-Info "Node.js LTS 설치 중... (1-2분 소요)"
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
    
    # Node.js 경로 추가
    $nodePaths = @(
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs"
    )
    foreach ($p in $nodePaths) {
        if (Test-Path $p) { Add-ToPath $p }
    }
    
    Update-Path
    if (Test-Command "node") {
        $nodeVer = node --version 2>$null
        Write-Success "Node.js 설치 완료! ($nodeVer)"
    } else {
        Write-Error-Custom "Node.js 설치 실패 - 새 터미널에서 확인 필요"
    }
}

# 4. Claude Code 설치
Write-Host ""
Write-Step "Claude Code 설치 중..."

try {
    # 공식 설치 스크립트 실행
    $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $installScript
    
    # Claude Code 경로들 추가
    $claudePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps",
        "$env:USERPROFILE\.claude\bin",
        "$env:USERPROFILE\.local\bin"
    )
    
    foreach ($p in $claudePaths) {
        if (Test-Path $p) { Add-ToPath $p }
    }
    
    Update-Path
    
    # 설치 확인
    Start-Sleep -Seconds 2
    
    if (Test-Command "claude") {
        $claudeVer = claude --version 2>$null
        Write-Success "Claude Code 설치 완료! ($claudeVer)"
    } else {
        # 직접 경로로 확인
        $claudeExe = Get-ChildItem -Path $claudePaths -Filter "claude*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($claudeExe) {
            Write-Success "Claude Code 설치 완료! (경로: $($claudeExe.Directory))"
            Write-Info "⚠️  새 터미널을 열어야 claude 명령어가 인식됩니다."
        } else {
            Write-Error-Custom "Claude Code 설치 확인 실패"
        }
    }
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
    Write-Info "수동 설치: irm https://claude.ai/install.ps1 | iex"
}

# 5. dsclaude 명령어 설치
Write-Host ""
Install-DsClaude

# 6. 최종 PATH 확인 및 적용
Write-Host ""
Write-Step "PATH 설정 최종 확인..."

# npm global 경로도 추가
$npmGlobalPath = "$env:APPDATA\npm"
if (Test-Path $npmGlobalPath) { Add-ToPath $npmGlobalPath }

Update-Path
Write-Success "PATH 설정 완료"

# ============================================================
# 완료 메시지
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📌 중요: 새 PowerShell 창을 열어주세요!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  사용 가능한 명령어:" -ForegroundColor White
Write-Host "     claude      - Claude Code 실행" -ForegroundColor Gray
Write-Host "     dsclaude    - 권한 확인 스킵 모드" -ForegroundColor Gray
Write-Host "                   (--dangerously-skip-permissions)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  시작하기:" -ForegroundColor White
Write-Host "     1. claude --version  (설치 확인)" -ForegroundColor Gray
Write-Host "     2. claude            (시작 & 로그인)" -ForegroundColor Gray
Write-Host ""

# 새 터미널 열기 제안
$openNew = Read-Host "새 PowerShell 창을 열까요? (Y/N)"
if ($openNew -eq "Y" -or $openNew -eq "y") {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host '✅ Claude Code 준비 완료!' -ForegroundColor Green; Write-Host ''; Write-Host '사용 가능한 명령어:' -ForegroundColor Cyan; Write-Host '  claude    - Claude Code 실행' -ForegroundColor White; Write-Host '  dsclaude  - 권한 스킵 모드 (--dangerously-skip-permissions)' -ForegroundColor White; Write-Host ''"
}