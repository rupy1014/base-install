<#
.SYNOPSIS
    Claude Code 설치 스크립트 (한글 경로 완벽 지원)
.DESCRIPTION
    npm 전역 경로를 영문으로 변경하여 Claude Code를 설치합니다.
    한글 사용자 이름으로 인한 경로 문제를 완전히 해결합니다.
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

function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

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

# ============================================================
# 설정
# ============================================================

$NpmGlobalPath = "C:\npm-global"
$ClaudeBinPath = "C:\claude-code\bin"

# ============================================================
# 메인
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 설치 (한글 경로 지원)      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 한글 경로 확인
$isKoreanPath = Test-NonAsciiPath $env:USERPROFILE
if ($isKoreanPath) {
    Write-Host "  ⚠️  한글 사용자 이름 감지: $env:USERNAME" -ForegroundColor Yellow
    Write-Host "     npm 전역 경로를 $NpmGlobalPath 로 설정합니다." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  ℹ️  영문 경로입니다. 표준 설치를 진행합니다." -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# 1. winget 확인
# ============================================================
Write-Step "winget 확인 중..."
if (-not (Test-Command "winget")) {
    Write-Error-Custom "winget이 설치되어 있지 않습니다."
    Write-Info "Windows 10 1709 이상 또는 Windows 11이 필요합니다."
    Write-Info "Microsoft Store에서 'App Installer'를 설치해주세요."
    Read-Host "Enter를 눌러 종료"
    exit 1
}
Write-Success "winget 확인됨"

# ============================================================
# 2. Git 설치
# ============================================================
Write-Step "Git 확인 중..."
Update-Path

if (Test-Command "git") {
    $gitVer = git --version 2>$null
    Write-Success "Git 이미 설치됨 ($gitVer)"
} else {
    Write-Info "Git 설치 중... (1-2분 소요)"
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    
    # Git PATH 추가
    if (Test-Path "$env:ProgramFiles\Git\cmd") {
        Add-ToPathPermanent "$env:ProgramFiles\Git\cmd" | Out-Null
    }
    
    Update-Path
    
    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Info "Git 설치됨 (새 터미널에서 확인 필요)"
    }
}

# ============================================================
# 3. Node.js 설치
# ============================================================
Write-Step "Node.js 확인 중..."
Update-Path

if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다 ($nodeVer). 업그레이드 중..."
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
        Update-Path
    }
} else {
    Write-Info "Node.js LTS 설치 중... (1-2분 소요)"
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    
    if (Test-Path "$env:ProgramFiles\nodejs") {
        Add-ToPathPermanent "$env:ProgramFiles\nodejs" | Out-Null
    }
    
    Update-Path
    
    if (Test-Command "node") {
        $nodeVer = node --version 2>$null
        Write-Success "Node.js 설치 완료! ($nodeVer)"
    } else {
        Write-Error-Custom "Node.js 설치 실패"
        Write-Info "수동 설치 필요: https://nodejs.org"
        Read-Host "Enter를 눌러 종료"
        exit 1
    }
}

# npm 확인
if (-not (Test-Command "npm")) {
    Write-Error-Custom "npm을 찾을 수 없습니다."
    Write-Info "Node.js를 다시 설치해주세요."
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# ============================================================
# 4. npm 전역 경로 설정 (한글 경로 우회)
# ============================================================
Write-Step "npm 전역 경로 설정 중..."

# 디렉토리 생성
if (-not (Test-Path $NpmGlobalPath)) {
    New-Item -ItemType Directory -Path $NpmGlobalPath -Force | Out-Null
    Write-Info "디렉토리 생성: $NpmGlobalPath"
}

# npm prefix 설정
$currentPrefix = npm config get prefix 2>$null
Write-Info "현재 npm prefix: $currentPrefix"

if ($currentPrefix -ne $NpmGlobalPath) {
    npm config set prefix $NpmGlobalPath
    Write-Info "npm prefix 변경: $NpmGlobalPath"
}

# PATH에 추가
Add-ToPathPermanent $NpmGlobalPath | Out-Null

Write-Success "npm 전역 경로 설정 완료"

# ============================================================
# 5. Claude Code 설치 (npm)
# ============================================================
Write-Step "Claude Code 설치 중 (npm)..."
Write-Info "npm install -g @anthropic-ai/claude-code"
Write-Info "설치에 1-3분 정도 소요됩니다..."

try {
    $installResult = npm install -g @anthropic-ai/claude-code 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Claude Code npm 설치 완료!"
    } else {
        Write-Warning "npm 설치 경고 발생 (계속 진행)"
        Write-Info $installResult
    }
} catch {
    Write-Error-Custom "npm 설치 실패: $_"
}

# 설치 확인
Write-Step "Claude Code 설치 확인 중..."

$claudeCmd = "$NpmGlobalPath\claude.cmd"
$claudeExe = "$NpmGlobalPath\claude.exe"

$claudePath = $null
if (Test-Path $claudeCmd) {
    $claudePath = $claudeCmd
    Write-Success "발견: $claudeCmd"
} elseif (Test-Path $claudeExe) {
    $claudePath = $claudeExe
    Write-Success "발견: $claudeExe"
} else {
    # node_modules 내부 검색
    $nodeModulesPath = "$NpmGlobalPath\node_modules\@anthropic-ai\claude-code"
    if (Test-Path $nodeModulesPath) {
        Write-Info "패키지 설치됨: $nodeModulesPath"
        
        # bin 파일 검색
        $binFiles = Get-ChildItem -Path $NpmGlobalPath -Filter "claude*" -ErrorAction SilentlyContinue
        if ($binFiles) {
            $claudePath = $binFiles[0].FullName
            Write-Success "발견: $claudePath"
        }
    }
}

if (-not $claudePath) {
    Write-Error-Custom "Claude Code 설치 파일을 찾을 수 없습니다."
    Write-Info "다음 경로를 확인해주세요: $NpmGlobalPath"
    Get-ChildItem $NpmGlobalPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Info "  $($_.Name)" }
}

# ============================================================
# 6. dsclaude 래퍼 생성
# ============================================================
Write-Step "dsclaude 래퍼 생성 중..."

if (-not (Test-Path $ClaudeBinPath)) {
    New-Item -ItemType Directory -Path $ClaudeBinPath -Force | Out-Null
}

# dsclaude.cmd 생성
$dsclaudeContent = @"
@echo off
chcp 65001 >nul 2>&1
claude --dangerously-skip-permissions %*
"@

$dsclaudePath = "$ClaudeBinPath\dsclaude.cmd"
Set-Content -Path $dsclaudePath -Value $dsclaudeContent -Encoding ASCII -Force

if (Test-Path $dsclaudePath) {
    Write-Success "dsclaude.cmd 생성됨: $dsclaudePath"
    Add-ToPathPermanent $ClaudeBinPath | Out-Null
} else {
    Write-Error-Custom "dsclaude.cmd 생성 실패"
}

# ============================================================
# 7. 최종 PATH 설정 및 확인
# ============================================================
Write-Step "최종 PATH 설정 중..."

# 모든 경로 추가 확인
Add-ToPathPermanent $NpmGlobalPath | Out-Null
Add-ToPathPermanent $ClaudeBinPath | Out-Null

Update-Path

# PATH 검증
Write-Step "설치 검증 중..."

$verifyOk = $true

# npm 전역 경로 확인
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$NpmGlobalPath*") {
    Write-Success "npm 전역 경로 PATH 등록됨"
} else {
    Write-Error-Custom "npm 전역 경로 PATH 등록 실패"
    $verifyOk = $false
}

# claude 명령어 테스트
Write-Info "claude 명령어 테스트..."
try {
    $claudeVersion = & claude --version 2>$null
    if ($claudeVersion) {
        Write-Success "claude 명령어 작동: $claudeVersion"
    } else {
        Write-Info "claude 명령어 응답 없음 (새 터미널에서 확인 필요)"
    }
} catch {
    Write-Info "claude 테스트 실패 (새 터미널에서 확인 필요)"
}

# ============================================================
# 완료
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📌 중요: 새 PowerShell/터미널 창을 열어주세요!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  설치된 명령어:" -ForegroundColor White
Write-Host "     claude      - Claude Code 실행" -ForegroundColor Gray
Write-Host "     dsclaude    - 권한 스킵 모드" -ForegroundColor Gray
Write-Host ""
Write-Host "  설치 경로:" -ForegroundColor White
Write-Host "     npm 전역: $NpmGlobalPath" -ForegroundColor Gray
Write-Host "     dsclaude: $ClaudeBinPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  시작하기:" -ForegroundColor White
Write-Host "     1. 새 터미널 열기" -ForegroundColor Gray
Write-Host "     2. claude --version" -ForegroundColor Gray
Write-Host "     3. claude" -ForegroundColor Gray
Write-Host ""

if (-not $verifyOk) {
    Write-Host "  ⚠️  PATH 등록이 실패한 경우 수동 추가:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  # PowerShell에서 실행:" -ForegroundColor Cyan
    Write-Host "  `$p = [Environment]::GetEnvironmentVariable('Path', 'User')" -ForegroundColor White
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"`$p;$NpmGlobalPath;$ClaudeBinPath`", 'User')" -ForegroundColor White
    Write-Host ""
}

$openNew = Read-Host "새 PowerShell을 열까요? (Y/N)"
if ($openNew -eq "Y" -or $openNew -eq "y") {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Write-Host '✅ Claude Code 테스트' -ForegroundColor Green; claude --version; Write-Host ''; Write-Host '사용: claude, dsclaude' -ForegroundColor Cyan"
}