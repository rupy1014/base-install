<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치하고 PATH 설정까지 완료합니다.
    dsclaude 명령어도 함께 설치됩니다.
    
    ⚠️ 한글 사용자 이름 디렉토리 문제 해결 버전
#>

# UTF-8 인코딩 설정
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 콘솔 출력 함수
function Write-Step { param([string]$Message) Write-Host "▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }
function Write-Warning-Custom { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor DarkYellow }

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# 경로에 비-ASCII 문자(한글 등) 포함 여부 확인
function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# 8.3 짧은 경로로 변환 (한글 경로 문제 해결)
function Get-ShortPath {
    param([string]$LongPath)
    
    if (-not (Test-Path $LongPath)) {
        return $LongPath
    }
    
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $LongPath -PathType Container) {
            return $fso.GetFolder($LongPath).ShortPath
        } else {
            return $fso.GetFile($LongPath).ShortPath
        }
    } catch {
        return $LongPath
    }
}

# 안전한 경로 반환 (한글 포함시 Short Path 또는 대체 경로)
function Get-SafePath {
    param(
        [string]$OriginalPath,
        [string]$FallbackPath = $null
    )
    
    if (Test-NonAsciiPath $OriginalPath) {
        # 먼저 Short Path 시도
        if (Test-Path $OriginalPath) {
            $shortPath = Get-ShortPath $OriginalPath
            if (-not (Test-NonAsciiPath $shortPath)) {
                return $shortPath
            }
        }
        
        # Short Path도 안되면 Fallback 사용
        if ($FallbackPath) {
            return $FallbackPath
        }
    }
    
    return $OriginalPath
}

# PATH 새로고침 (시스템 + 사용자)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH에 경로 추가 (영구적 + 현재 세션)
function Add-ToPath {
    param([string]$NewPath)
    
    if (-not (Test-Path $NewPath)) { return $false }
    
    # 한글 경로면 Short Path로 변환
    $safePath = $NewPath
    if (Test-NonAsciiPath $NewPath) {
        $safePath = Get-ShortPath $NewPath
        if ($safePath -ne $NewPath) {
            Write-Info "한글 경로 변환: $NewPath → $safePath"
        }
    }
    
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentUserPath -notlike "*$safePath*") {
        $newUserPath = if ($currentUserPath) { "$currentUserPath;$safePath" } else { $safePath }
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Info "PATH에 추가됨: $safePath"
    }
    
    # 현재 세션에도 적용
    if ($env:Path -notlike "*$safePath*") {
        $env:Path = "$env:Path;$safePath"
    }
    
    return $true
}

# 안전한 bin 디렉토리 결정 (한글 경로 회피)
function Get-SafeBinPath {
    $userBin = "$env:USERPROFILE\.local\bin"
    $globalBin = "C:\claude-code\bin"
    
    if (Test-NonAsciiPath $env:USERPROFILE) {
        Write-Warning-Custom "한글 사용자 이름 감지: $env:USERNAME"
        Write-Info "대체 경로 사용: $globalBin"
        
        if (-not (Test-Path $globalBin)) {
            New-Item -ItemType Directory -Path $globalBin -Force | Out-Null
        }
        return $globalBin
    }
    
    if (-not (Test-Path $userBin)) {
        New-Item -ItemType Directory -Path $userBin -Force | Out-Null
    }
    return $userBin
}

# Claude Code 실행 파일 찾기
function Find-ClaudeExecutable {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code\claude.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\claude.exe",
        "$env:USERPROFILE\.claude\bin\claude.exe",
        "$env:USERPROFILE\.local\bin\claude.exe",
        "C:\claude-code\bin\claude.exe",
        "C:\Program Files\claude-code\claude.exe"
    )
    
    # 한글 경로인 경우 Short Path로도 시도
    $allPaths = @()
    foreach ($p in $possiblePaths) {
        $allPaths += $p
        if (Test-NonAsciiPath $p) {
            $parent = Split-Path $p -Parent
            if (Test-Path $parent) {
                $shortParent = Get-ShortPath $parent
                $fileName = Split-Path $p -Leaf
                $allPaths += "$shortParent\$fileName"
            }
        }
    }
    
    foreach ($path in $allPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # where.exe로 검색
    $whereClaude = where.exe claude 2>$null | Select-Object -First 1
    if ($whereClaude -and (Test-Path $whereClaude)) {
        return $whereClaude
    }
    
    return $null
}

# dsclaude 명령어 생성
function Install-DsClaude {
    param([string]$ClaudePath = $null)
    
    Write-Step "dsclaude 명령어 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    # 기존 파일들 정리
    $oldFiles = @("$binPath\dsclaude.ps1", "$binPath\dsclaude.bat")
    foreach ($f in $oldFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Claude 경로 결정
    $claudeCmd = "claude"
    if ($ClaudePath -and (Test-Path $ClaudePath)) {
        # 한글 경로면 Short Path 사용
        if (Test-NonAsciiPath $ClaudePath) {
            $claudeCmd = Get-ShortPath $ClaudePath
        } else {
            $claudeCmd = $ClaudePath
        }
        $claudeCmd = "`"$claudeCmd`""
    }
    
    # dsclaude.cmd 파일 생성
    $dsclaudeCmd = @"
@echo off
chcp 65001 >nul 2>&1
$claudeCmd --dangerously-skip-permissions %*
"@
    
    $cmdPath = "$binPath\dsclaude.cmd"
    Set-Content -Path $cmdPath -Value $dsclaudeCmd -Encoding ASCII
    
    # PATH에 추가
    Add-ToPath $binPath | Out-Null
    
    if (Test-Path $cmdPath) {
        Write-Success "dsclaude 명령어 생성 완료!"
        Write-Info "위치: $cmdPath"
        return $true
    } else {
        Write-Error-Custom "dsclaude 생성 실패"
        return $false
    }
}

# Claude 래퍼 스크립트 생성 (한글 경로 문제 해결용)
function Install-ClaudeWrapper {
    param([string]$ClaudePath)
    
    if (-not $ClaudePath -or -not (Test-Path $ClaudePath)) {
        return $false
    }
    
    $binPath = Get-SafeBinPath
    
    # Short Path 변환
    $safeClaudePath = $ClaudePath
    if (Test-NonAsciiPath $ClaudePath) {
        $safeClaudePath = Get-ShortPath $ClaudePath
    }
    
    # claude.cmd 래퍼 생성
    $claudeWrapper = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" %*
"@
    
    $wrapperPath = "$binPath\claude.cmd"
    Set-Content -Path $wrapperPath -Value $claudeWrapper -Encoding ASCII
    
    Write-Info "Claude 래퍼 생성: $wrapperPath"
    return $true
}

# ============================================================
# 메인 설치
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 원클릭 설치 스크립트       ║" -ForegroundColor Cyan
Write-Host "  ║   (한글 경로 지원 버전)                  ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 한글 사용자 이름 경고
if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host ""
    Write-Host "  ⚠️  한글 사용자 이름이 감지되었습니다!" -ForegroundColor Yellow
    Write-Host "     사용자: $env:USERNAME" -ForegroundColor Gray
    Write-Host "     일부 경로를 대체 위치에 설정합니다." -ForegroundColor Gray
    Write-Host ""
}

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
        if (Test-Path $p) { Add-ToPath $p | Out-Null }
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
        if (Test-Path $p) { Add-ToPath $p | Out-Null }
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

$claudeExePath = $null

try {
    # 공식 설치 스크립트 실행
    $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $installScript
    
    Start-Sleep -Seconds 3
    
    # Claude Code 경로들 추가
    $claudePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps",
        "$env:USERPROFILE\.claude\bin",
        "$env:USERPROFILE\.local\bin",
        "C:\claude-code\bin"
    )
    
    foreach ($p in $claudePaths) {
        if (Test-Path $p) { 
            Add-ToPath $p | Out-Null
        }
    }
    
    Update-Path
    
    # Claude 실행 파일 찾기
    $claudeExePath = Find-ClaudeExecutable
    
    if ($claudeExePath) {
        Write-Success "Claude Code 발견: $claudeExePath"
        
        # 한글 경로인 경우 래퍼 생성
        if (Test-NonAsciiPath $claudeExePath) {
            Write-Warning-Custom "Claude가 한글 경로에 설치되어 있습니다."
            Write-Info "래퍼 스크립트를 생성합니다..."
            Install-ClaudeWrapper -ClaudePath $claudeExePath
        }
        
        # 버전 확인
        if (Test-Command "claude") {
            $claudeVer = claude --version 2>$null
            Write-Success "Claude Code 설치 완료! ($claudeVer)"
        } else {
            Write-Success "Claude Code 설치 완료!"
            Write-Info "⚠️  새 터미널을 열어야 claude 명령어가 인식됩니다."
        }
    } else {
        Write-Error-Custom "Claude Code 실행 파일을 찾을 수 없습니다."
        Write-Info "수동 설치 필요: irm https://claude.ai/install.ps1 | iex"
    }
    
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
    Write-Info "수동 설치: irm https://claude.ai/install.ps1 | iex"
}

# 5. dsclaude 명령어 설치
Write-Host ""
Install-DsClaude -ClaudePath $claudeExePath

# 6. 최종 PATH 확인 및 적용
Write-Host ""
Write-Step "PATH 설정 최종 확인..."

# npm global 경로도 추가
$npmGlobalPath = "$env:APPDATA\npm"
if (Test-Path $npmGlobalPath) { 
    Add-ToPath $npmGlobalPath | Out-Null 
}

# 안전한 bin 경로가 PATH에 있는지 확인
$safeBin = Get-SafeBinPath
Add-ToPath $safeBin | Out-Null

Update-Path
Write-Success "PATH 설정 완료"

# 설치 경로 요약
Write-Host ""
Write-Step "설치 경로 요약:"
Write-Info "안전한 bin 경로: $safeBin"
if ($claudeExePath) {
    Write-Info "Claude 실행 파일: $claudeExePath"
    if (Test-NonAsciiPath $claudeExePath) {
        $shortPath = Get-ShortPath $claudeExePath
        Write-Info "Short Path: $shortPath"
    }
}

# ============================================================
# 완료 메시지
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host "  ℹ️  한글 사용자 이름 환경 설정 완료" -ForegroundColor Cyan
    Write-Host "     래퍼 스크립트 위치: $safeBin" -ForegroundColor Gray
    Write-Host ""
}

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
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "chcp 65001 | Out-Null; Write-Host '✅ Claude Code 준비 완료!' -ForegroundColor Green; Write-Host ''; Write-Host '사용 가능한 명령어:' -ForegroundColor Cyan; Write-Host '  claude    - Claude Code 실행' -ForegroundColor White; Write-Host '  dsclaude  - 권한 스킵 모드' -ForegroundColor White; Write-Host ''"
}<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치하고 PATH 설정까지 완료합니다.
    dsclaude 명령어도 함께 설치됩니다.
    
    ⚠️ 한글 사용자 이름 디렉토리 문제 해결 버전
#>

# UTF-8 인코딩 설정
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 콘솔 출력 함수
function Write-Step { param([string]$Message) Write-Host "▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }
function Write-Warning-Custom { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor DarkYellow }

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# 경로에 비-ASCII 문자(한글 등) 포함 여부 확인
function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# 8.3 짧은 경로로 변환 (한글 경로 문제 해결)
function Get-ShortPath {
    param([string]$LongPath)
    
    if (-not (Test-Path $LongPath)) {
        return $LongPath
    }
    
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $LongPath -PathType Container) {
            return $fso.GetFolder($LongPath).ShortPath
        } else {
            return $fso.GetFile($LongPath).ShortPath
        }
    } catch {
        return $LongPath
    }
}

# 안전한 경로 반환 (한글 포함시 Short Path 또는 대체 경로)
function Get-SafePath {
    param(
        [string]$OriginalPath,
        [string]$FallbackPath = $null
    )
    
    if (Test-NonAsciiPath $OriginalPath) {
        # 먼저 Short Path 시도
        if (Test-Path $OriginalPath) {
            $shortPath = Get-ShortPath $OriginalPath
            if (-not (Test-NonAsciiPath $shortPath)) {
                return $shortPath
            }
        }
        
        # Short Path도 안되면 Fallback 사용
        if ($FallbackPath) {
            return $FallbackPath
        }
    }
    
    return $OriginalPath
}

# PATH 새로고침 (시스템 + 사용자)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH에 경로 추가 (영구적 + 현재 세션)
function Add-ToPath {
    param([string]$NewPath)
    
    if (-not (Test-Path $NewPath)) { return $false }
    
    # 한글 경로면 Short Path로 변환
    $safePath = $NewPath
    if (Test-NonAsciiPath $NewPath) {
        $safePath = Get-ShortPath $NewPath
        if ($safePath -ne $NewPath) {
            Write-Info "한글 경로 변환: $NewPath → $safePath"
        }
    }
    
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentUserPath -notlike "*$safePath*") {
        $newUserPath = if ($currentUserPath) { "$currentUserPath;$safePath" } else { $safePath }
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Info "PATH에 추가됨: $safePath"
    }
    
    # 현재 세션에도 적용
    if ($env:Path -notlike "*$safePath*") {
        $env:Path = "$env:Path;$safePath"
    }
    
    return $true
}

# 안전한 bin 디렉토리 결정 (한글 경로 회피)
function Get-SafeBinPath {
    $userBin = "$env:USERPROFILE\.local\bin"
    $globalBin = "C:\claude-code\bin"
    
    if (Test-NonAsciiPath $env:USERPROFILE) {
        Write-Warning-Custom "한글 사용자 이름 감지: $env:USERNAME"
        Write-Info "대체 경로 사용: $globalBin"
        
        if (-not (Test-Path $globalBin)) {
            New-Item -ItemType Directory -Path $globalBin -Force | Out-Null
        }
        return $globalBin
    }
    
    if (-not (Test-Path $userBin)) {
        New-Item -ItemType Directory -Path $userBin -Force | Out-Null
    }
    return $userBin
}

# Claude Code 실행 파일 찾기
function Find-ClaudeExecutable {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code\claude.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\claude.exe",
        "$env:USERPROFILE\.claude\bin\claude.exe",
        "$env:USERPROFILE\.local\bin\claude.exe",
        "C:\claude-code\bin\claude.exe",
        "C:\Program Files\claude-code\claude.exe"
    )
    
    # 한글 경로인 경우 Short Path로도 시도
    $allPaths = @()
    foreach ($p in $possiblePaths) {
        $allPaths += $p
        if (Test-NonAsciiPath $p) {
            $parent = Split-Path $p -Parent
            if (Test-Path $parent) {
                $shortParent = Get-ShortPath $parent
                $fileName = Split-Path $p -Leaf
                $allPaths += "$shortParent\$fileName"
            }
        }
    }
    
    foreach ($path in $allPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # where.exe로 검색
    $whereClaude = where.exe claude 2>$null | Select-Object -First 1
    if ($whereClaude -and (Test-Path $whereClaude)) {
        return $whereClaude
    }
    
    return $null
}

# dsclaude 명령어 생성
function Install-DsClaude {
    param([string]$ClaudePath = $null)
    
    Write-Step "dsclaude 명령어 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    # 기존 파일들 정리
    $oldFiles = @("$binPath\dsclaude.ps1", "$binPath\dsclaude.bat")
    foreach ($f in $oldFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Claude 경로 결정
    $claudeCmd = "claude"
    if ($ClaudePath -and (Test-Path $ClaudePath)) {
        # 한글 경로면 Short Path 사용
        if (Test-NonAsciiPath $ClaudePath) {
            $claudeCmd = Get-ShortPath $ClaudePath
        } else {
            $claudeCmd = $ClaudePath
        }
        $claudeCmd = "`"$claudeCmd`""
    }
    
    # dsclaude.cmd 파일 생성
    $dsclaudeCmd = @"
@echo off
chcp 65001 >nul 2>&1
$claudeCmd --dangerously-skip-permissions %*
"@
    
    $cmdPath = "$binPath\dsclaude.cmd"
    Set-Content -Path $cmdPath -Value $dsclaudeCmd -Encoding ASCII
    
    # PATH에 추가
    Add-ToPath $binPath | Out-Null
    
    if (Test-Path $cmdPath) {
        Write-Success "dsclaude 명령어 생성 완료!"
        Write-Info "위치: $cmdPath"
        return $true
    } else {
        Write-Error-Custom "dsclaude 생성 실패"
        return $false
    }
}

# Claude 래퍼 스크립트 생성 (한글 경로 문제 해결용)
function Install-ClaudeWrapper {
    param([string]$ClaudePath)
    
    if (-not $ClaudePath -or -not (Test-Path $ClaudePath)) {
        return $false
    }
    
    $binPath = Get-SafeBinPath
    
    # Short Path 변환
    $safeClaudePath = $ClaudePath
    if (Test-NonAsciiPath $ClaudePath) {
        $safeClaudePath = Get-ShortPath $ClaudePath
    }
    
    # claude.cmd 래퍼 생성
    $claudeWrapper = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" %*
"@
    
    $wrapperPath = "$binPath\claude.cmd"
    Set-Content -Path $wrapperPath -Value $claudeWrapper -Encoding ASCII
    
    Write-Info "Claude 래퍼 생성: $wrapperPath"
    return $true
}

# ============================================================
# 메인 설치
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 원클릭 설치 스크립트       ║" -ForegroundColor Cyan
Write-Host "  ║   (한글 경로 지원 버전)                  ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 한글 사용자 이름 경고
if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host ""
    Write-Host "  ⚠️  한글 사용자 이름이 감지되었습니다!" -ForegroundColor Yellow
    Write-Host "     사용자: $env:USERNAME" -ForegroundColor Gray
    Write-Host "     일부 경로를 대체 위치에 설정합니다." -ForegroundColor Gray
    Write-Host ""
}

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
        if (Test-Path $p) { Add-ToPath $p | Out-Null }
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
        if (Test-Path $p) { Add-ToPath $p | Out-Null }
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

$claudeExePath = $null

try {
    # 공식 설치 스크립트 실행
    $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $installScript
    
    Start-Sleep -Seconds 3
    
    # Claude Code 경로들 추가
    $claudePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps",
        "$env:USERPROFILE\.claude\bin",
        "$env:USERPROFILE\.local\bin",
        "C:\claude-code\bin"
    )
    
    foreach ($p in $claudePaths) {
        if (Test-Path $p) { 
            Add-ToPath $p | Out-Null
        }
    }
    
    Update-Path
    
    # Claude 실행 파일 찾기
    $claudeExePath = Find-ClaudeExecutable
    
    if ($claudeExePath) {
        Write-Success "Claude Code 발견: $claudeExePath"
        
        # 한글 경로인 경우 래퍼 생성
        if (Test-NonAsciiPath $claudeExePath) {
            Write-Warning-Custom "Claude가 한글 경로에 설치되어 있습니다."
            Write-Info "래퍼 스크립트를 생성합니다..."
            Install-ClaudeWrapper -ClaudePath $claudeExePath
        }
        
        # 버전 확인
        if (Test-Command "claude") {
            $claudeVer = claude --version 2>$null
            Write-Success "Claude Code 설치 완료! ($claudeVer)"
        } else {
            Write-Success "Claude Code 설치 완료!"
            Write-Info "⚠️  새 터미널을 열어야 claude 명령어가 인식됩니다."
        }
    } else {
        Write-Error-Custom "Claude Code 실행 파일을 찾을 수 없습니다."
        Write-Info "수동 설치 필요: irm https://claude.ai/install.ps1 | iex"
    }
    
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
    Write-Info "수동 설치: irm https://claude.ai/install.ps1 | iex"
}

# 5. dsclaude 명령어 설치
Write-Host ""
Install-DsClaude -ClaudePath $claudeExePath

# 6. 최종 PATH 확인 및 적용
Write-Host ""
Write-Step "PATH 설정 최종 확인..."

# npm global 경로도 추가
$npmGlobalPath = "$env:APPDATA\npm"
if (Test-Path $npmGlobalPath) { 
    Add-ToPath $npmGlobalPath | Out-Null 
}

# 안전한 bin 경로가 PATH에 있는지 확인
$safeBin = Get-SafeBinPath
Add-ToPath $safeBin | Out-Null

Update-Path
Write-Success "PATH 설정 완료"

# 설치 경로 요약
Write-Host ""
Write-Step "설치 경로 요약:"
Write-Info "안전한 bin 경로: $safeBin"
if ($claudeExePath) {
    Write-Info "Claude 실행 파일: $claudeExePath"
    if (Test-NonAsciiPath $claudeExePath) {
        $shortPath = Get-ShortPath $claudeExePath
        Write-Info "Short Path: $shortPath"
    }
}

# ============================================================
# 완료 메시지
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if (Test-NonAsciiPath $env:USERPROFILE) {
    Write-Host "  ℹ️  한글 사용자 이름 환경 설정 완료" -ForegroundColor Cyan
    Write-Host "     래퍼 스크립트 위치: $safeBin" -ForegroundColor Gray
    Write-Host ""
}

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
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "chcp 65001 | Out-Null; Write-Host '✅ Claude Code 준비 완료!' -ForegroundColor Green; Write-Host ''; Write-Host '사용 가능한 명령어:' -ForegroundColor Cyan; Write-Host '  claude    - Claude Code 실행' -ForegroundColor White; Write-Host '  dsclaude  - 권한 스킵 모드' -ForegroundColor White; Write-Host ''"
}