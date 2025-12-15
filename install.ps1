<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치합니다.
#>

# 콘솔 출력 함수
function Write-Step { param([string]$Message) Write-Host "▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# PATH 새로고침
function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
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
if (-not (Test-Command "winget")) {
    Write-Error-Custom "winget이 설치되어 있지 않습니다."
    Write-Info "Windows 10 1709 이상 또는 Windows 11이 필요합니다."
    Write-Info "Microsoft Store에서 'App Installer'를 설치해주세요."
    exit 1
}

# 2. Git 설치
Write-Step "Git 확인 중..."
if (Test-Command "git") {
    $gitVer = git --version 2>$null
    Write-Success "Git 이미 설치됨 ($gitVer)"
} else {
    Write-Info "Git 설치 중..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
    Update-Path
    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Error-Custom "Git 설치 실패"
    }
}

# 3. Node.js 설치
Write-Host ""
Write-Step "Node.js 확인 중..."
if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다. 업그레이드 중..."
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
        Update-Path
    }
} else {
    Write-Info "Node.js LTS 설치 중..."
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
    Update-Path
    if (Test-Command "node") {
        $nodeVer = node --version 2>$null
        Write-Success "Node.js 설치 완료! ($nodeVer)"
    } else {
        Write-Error-Custom "Node.js 설치 실패"
    }
}

# 4. Claude Code 설치
Write-Host ""
Write-Step "Claude Code 설치 중..."
try {
    irm https://claude.ai/install.ps1 | iex
    Write-Success "Claude Code 설치 완료!"
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
    Write-Info "수동 설치: irm https://claude.ai/install.ps1 | iex"
}

# 완료 메시지
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📌 다음 단계:" -ForegroundColor White
Write-Host "     1. 새 터미널(PowerShell)을 열어주세요" -ForegroundColor Gray
Write-Host "     2. claude 명령어로 시작!" -ForegroundColor Gray
Write-Host ""